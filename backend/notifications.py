from flasgger import swag_from
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import get_current_user_id, db, load_yaml
from websocket_handler import broadcast_to_users

notifications_blueprint = Blueprint('notifications', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)

NOTIFICATION_TYPE_MESSAGE = 1
NOTIFICATION_TYPE_GROUP_ACTIVITY_CREATED = 2
NOTIFICATION_TYPE_MEMBERSHIP_REQUEST = 3
NOTIFICATION_TYPE_ACTIVITY_ASSIGNED = 4


def _safe_broadcast_notification(recipient_user_id: int, payload: dict):
    try:
        broadcast_to_users([recipient_user_id], payload)
    except:
        pass


def create_membership_request_notification(
    recipient_user_id: int,
    requester_user_id: int,
    requester_username: str,
    target_type: str,
    target_id: int,
    target_name: str,
):
    with db.cursor(cursor_factory=RealDictCursor) as local_cursor:
        local_cursor.execute(
            """
            INSERT INTO notification (type)
            VALUES (%s)
            RETURNING id_notification, created_at
            """,
            (NOTIFICATION_TYPE_MEMBERSHIP_REQUEST,),
        )
        notif = local_cursor.fetchone()
        notif_id = notif["id_notification"]
        created_at = notif["created_at"]

        local_cursor.execute(
            """
            INSERT INTO user_notification (notification_id, user_id)
            VALUES (%s, %s)
            """,
            (notif_id, recipient_user_id),
        )
        local_cursor.execute(
            """
            INSERT INTO membership_request_notification
            (notification_id, requester_user_id, target_type, target_id, status)
            VALUES (%s, %s, %s, %s, 'pending')
            """,
            (notif_id, requester_user_id, target_type, target_id),
        )
        db.commit()

    _safe_broadcast_notification(
        recipient_user_id,
        {
            "type": "new_notification",
            "notification_id": notif_id,
            "notification_type": NOTIFICATION_TYPE_MEMBERSHIP_REQUEST,
            "created_at": created_at.isoformat() if created_at else None,
            "requester_username": requester_username,
            "target_type": target_type,
            "target_id": target_id,
            "target_name": target_name,
            "status": "pending",
        },
    )


def create_activity_assigned_notification(
    recipient_user_id: int,
    activity_id: int,
    activity_name: str,
    assigned_by_user_id: int,
    assigned_by_username: str,
):
    with db.cursor(cursor_factory=RealDictCursor) as local_cursor:
        local_cursor.execute(
            """
            INSERT INTO notification (type)
            VALUES (%s)
            RETURNING id_notification, created_at
            """,
            (NOTIFICATION_TYPE_ACTIVITY_ASSIGNED,),
        )
        notif = local_cursor.fetchone()
        notif_id = notif["id_notification"]
        created_at = notif["created_at"]

        local_cursor.execute(
            """
            INSERT INTO user_notification (notification_id, user_id)
            VALUES (%s, %s)
            """,
            (notif_id, recipient_user_id),
        )
        local_cursor.execute(
            """
            INSERT INTO activity_assignment_notification
            (notification_id, activity_id, assigned_by_user_id)
            VALUES (%s, %s, %s)
            """,
            (notif_id, activity_id, assigned_by_user_id),
        )
        db.commit()

    _safe_broadcast_notification(
        recipient_user_id,
        {
            "type": "new_notification",
            "notification_id": notif_id,
            "notification_type": NOTIFICATION_TYPE_ACTIVITY_ASSIGNED,
            "created_at": created_at.isoformat() if created_at else None,
            "activity_id": activity_id,
            "activity_name": activity_name,
            "assigned_by_username": assigned_by_username,
        },
    )

@notifications_blueprint.route('', methods=["GET"])
@jwt_required()
@swag_from(load_yaml("documentation/notifications.yaml", "get_notifications"))
# Lists all notifications for the authenticated user
def get_notifications():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute(
        """
        SELECT
            n.id_notification,
            n.type,
            n.created_at,
            mrn.status AS membership_status,
            mrn.target_type AS membership_target_type,
            mrn.target_id AS membership_target_id,
            u_req.username AS requester_username,
            g.name AS group_name,
            c.name AS conversation_name,
            aan.activity_id AS assigned_activity_id,
            a.name AS assigned_activity_name,
            u_assigner.username AS assigned_by_username
        FROM notification n
        JOIN user_notification un ON n.id_notification = un.notification_id
        LEFT JOIN membership_request_notification mrn ON n.id_notification = mrn.notification_id
        LEFT JOIN "user" u_req ON mrn.requester_user_id = u_req.id_registration
        LEFT JOIN "group" g ON mrn.target_type = 'group' AND mrn.target_id = g.id_group
        LEFT JOIN conversation c ON mrn.target_type = 'conversation' AND mrn.target_id = c.id
        LEFT JOIN activity_assignment_notification aan ON n.id_notification = aan.notification_id
        LEFT JOIN activity a ON aan.activity_id = a.id_activity
        LEFT JOIN "user" u_assigner ON aan.assigned_by_user_id = u_assigner.id_registration
        WHERE un.user_id = %s
        ORDER BY n.created_at DESC
        """,
        (current_user_id,),
    )
    notifications = cursor.fetchall()

    return {
        "message": "Success",
        "notifications": notifications
    }, 200

@notifications_blueprint.route('/<int:notif_id>', methods=["DELETE"])
@jwt_required()
@swag_from(load_yaml("documentation/notifications.yaml", "delete_notification"))
# This function was edited using AI (Gemini)
# Deletes a specific user notification. User can only delete their own.
def delete_notification(notif_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
                   SELECT 1
                   FROM user_notification
                   WHERE notification_id = %s AND user_id = %s
                   """, (notif_id, current_user_id))
    if cursor.fetchone() is None:
        return {
            "message": "Notification not found!"
        }, 404

    try:
        cursor.execute("""
                       DELETE
                       FROM user_notification
                       WHERE notification_id = %s
                         AND user_id = %s
                       """, (notif_id, current_user_id))
        db.commit()
    except:
        db.rollback()
        return {
            "message": "Failed to delete notification!"
        }, 500

    return {
        "message": "Notification deleted successfully"
    }, 200


@notifications_blueprint.route('/<int:notif_id>/respond', methods=["POST"])
@jwt_required()
def respond_membership_request(notif_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    if not request.is_json:
        return {"message": "Invalid format!"}, 400
    decision = str(request.json.get("decision", "")).strip().lower()
    if decision not in ("accept", "reject"):
        return {"message": "decision must be accept or reject"}, 400

    cursor.execute(
        """
        SELECT n.type, mrn.target_type, mrn.target_id, mrn.status
        FROM notification n
        JOIN user_notification un ON n.id_notification = un.notification_id
        JOIN membership_request_notification mrn ON n.id_notification = mrn.notification_id
        WHERE n.id_notification = %s AND un.user_id = %s
        """,
        (notif_id, current_user_id),
    )
    row = cursor.fetchone()
    if row is None:
        return {"message": "Notification not found!"}, 404
    if row["type"] != NOTIFICATION_TYPE_MEMBERSHIP_REQUEST:
        return {"message": "This notification cannot be responded to!"}, 400
    if row["status"] != "pending":
        return {"message": "This request was already processed."}, 409

    target_type = row["target_type"]
    target_id = row["target_id"]

    try:
        if decision == "accept":
            if target_type == "group":
                cursor.execute(
                    """
                    SELECT 1 FROM group_member
                    WHERE group_id = %s AND user_id = %s
                    """,
                    (target_id, current_user_id),
                )
                if cursor.fetchone() is None:
                    cursor.execute(
                        """
                        INSERT INTO group_member (group_id, user_id)
                        VALUES (%s, %s)
                        """,
                        (target_id, current_user_id),
                    )

                cursor.execute(
                    """
                    SELECT id_role FROM role
                    WHERE group_id = %s AND name = 'Member'
                    """,
                    (target_id,),
                )
                member_role = cursor.fetchone()
                if member_role is None:
                    cursor.execute(
                        """
                        INSERT INTO role (group_id, name, color)
                        VALUES (%s, 'Member', '#808080') RETURNING id_role
                        """,
                        (target_id,),
                    )
                    member_role = cursor.fetchone()
                    cursor.execute(
                        """
                        INSERT INTO role_permission (role_id, permission_id, value)
                        SELECT %s, id_permission, FALSE FROM permission
                        """,
                        (member_role["id_role"],),
                    )

                cursor.execute(
                    """
                    INSERT INTO user_role (user_id, role_id)
                    VALUES (%s, %s)
                    ON CONFLICT (user_id, role_id) DO NOTHING
                    """,
                    (current_user_id, member_role["id_role"]),
                )

                cursor.execute(
                    'SELECT conversation_id FROM "group" WHERE id_group = %s',
                    (target_id,),
                )
                group_row = cursor.fetchone()
                if group_row and group_row["conversation_id"]:
                    cursor.execute(
                        """
                        INSERT INTO participant (conversation_id, user_id)
                        VALUES (%s, %s)
                        ON CONFLICT (conversation_id, user_id) DO NOTHING
                        """,
                        (group_row["conversation_id"], current_user_id),
                    )

            elif target_type == "conversation":
                cursor.execute(
                    """
                    INSERT INTO participant (conversation_id, user_id)
                    VALUES (%s, %s)
                    ON CONFLICT (conversation_id, user_id) DO NOTHING
                    """,
                    (target_id, current_user_id),
                )
            else:
                return {"message": "Unknown request target type!"}, 400

        cursor.execute(
            """
            UPDATE membership_request_notification
            SET status = %s
            WHERE notification_id = %s
            """,
            ("accepted" if decision == "accept" else "rejected", notif_id),
        )
        db.commit()
    except Exception:
        db.rollback()
        return {"message": "Failed to process request!"}, 500

    return {
        "message": "Request accepted" if decision == "accept" else "Request rejected"
    }, 200