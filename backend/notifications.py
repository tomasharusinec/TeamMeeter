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
@swag_from(load_yaml("documentation/notifications.yaml", "get_notifications"))
# Lists all notifications for the authenticated user
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