from flasgger import swag_from
from flask import request
from flask_jwt_extended import jwt_required, get_jwt_identity
from psycopg2.extras import RealDictCursor
from flask import Blueprint
from helper_func import get_current_user_id, db, load_yaml

notifications_blueprint = Blueprint('notifications', __name__)
cursor = db.cursor(cursor_factory=RealDictCursor)


@notifications_blueprint.route('', methods=["GET"])
@jwt_required()
#@swag_from(load_yaml("documentation/notifications.yaml", "get_notifications"))
def get_notifications():
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
                   SELECT n.id_notification, n.type, n.created_at
                   FROM notification n
                            JOIN user_notification un ON n.id_notification = un.notification_id
                   WHERE un.user_id = %s
                   ORDER BY n.created_at DESC
                   """, (current_user_id,))
    notifications = cursor.fetchall()

    return {
        "message": "Success",
        "notifications": notifications
    }, 200


@notifications_blueprint.route('', methods=["POST"])
@jwt_required()
#@swag_from(load_yaml("documentation/notifications.yaml", "create_notification"))
def create_notification():
    try:
        notif_type = request.json["type"]
        user_ids = request.json["user_ids"]
        message_id = request.json.get("message_id")
        activity_id = request.json.get("activity_id")
    except:
        return {
            "message": "Invalid format!"
        }, 400

    try:
        cursor.execute("""
                       INSERT INTO notification (type)
                       VALUES (%s) RETURNING id_notification
                       """, (notif_type,))
        notif_id = cursor.fetchone()["id_notification"]

        for uid in user_ids:
            cursor.execute("""
                           INSERT INTO user_notification (notification_id, user_id)
                           VALUES (%s, %s)
                           """, (notif_id, uid))

        if message_id:
            cursor.execute("""
                           INSERT INTO message_notification (notification_id, message_id)
                           VALUES (%s, %s)
                           """, (notif_id, message_id))

        if activity_id:
            cursor.execute("""
                           INSERT INTO activity_notification (notification_id, activity_id)
                           VALUES (%s, %s)
                           """, (notif_id, activity_id))

        db.commit()
    except:
        db.rollback()
        return {
            "message": "Failed to create notification!"
        }, 500

    return {
        "message": "Notification created successfully",
        "notification_id": notif_id
    }, 201


@notifications_blueprint.route('/<int:notif_id>', methods=["DELETE"])
@jwt_required()
#@swag_from(load_yaml("documentation/notifications.yaml", "delete_notification"))
def delete_notification(notif_id):
    identity = get_jwt_identity()
    current_user_id = get_current_user_id(identity)

    cursor.execute("""
                   SELECT 1
                   FROM user_notification
                   WHERE notification_id = %s
                     AND user_id = %s
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