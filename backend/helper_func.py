import os
from dotenv import load_dotenv
import psycopg2
from psycopg2.extras import RealDictCursor

load_dotenv()
db = psycopg2.connect(host = "localhost", port = "5432", user = "postgres", password = os.getenv("MY_PASS"), database = "TeamsMeeter")
cursor = db.cursor(cursor_factory=RealDictCursor)

def check_permission(user_id, group_id, permission_name):
    cursor.execute("""
        SELECT rp.value FROM role_permission rp
        JOIN role r ON r.id_role = rp.role_id
        JOIN permission p ON p.id_permission = rp.permission_id
        JOIN user_role ur ON ur.role_id = r.id_role
        WHERE ur.user_id = %s AND r.group_id = %s AND p.name = %s AND rp.value = TRUE
    """, (user_id, group_id, permission_name))
    return cursor.fetchone() is not None


def is_group_member(user_id, group_id):
    cursor.execute("""
        SELECT 1 FROM group_member WHERE user_id = %s AND group_id = %s
    """, (user_id, group_id))
    return cursor.fetchone() is not None

def get_current_user_id(identity):
    cursor.execute('SELECT id_registration FROM "user" WHERE username = %s', (identity,))
    result = cursor.fetchone()
    if result:
        return result["id_registration"]
    return None