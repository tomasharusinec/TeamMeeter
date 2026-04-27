import json
import os
from dotenv import load_dotenv
import psycopg2
from psycopg2.extras import RealDictCursor
import yaml

load_dotenv()
db = psycopg2.connect(
    host=os.getenv("DB_HOST", "localhost"),
    port=os.getenv("DB_PORT", "5432"),
    user=os.getenv("DB_USER", "postgres"),
    password=os.getenv("MY_PASS"),
    database=os.getenv("DB_NAME", "TeamsMeeter")
)
cursor = db.cursor(cursor_factory=RealDictCursor)

# Verifies if a user has a specific permission in a group
def check_permission(user_id, group_id, permission_name):
    cursor.execute("""
        SELECT 1
        FROM user_role ur
        JOIN role r ON ur.role_id = r.id_role
        LEFT JOIN role_permission rp ON rp.role_id = r.id_role
        LEFT JOIN permission p ON p.id_permission = rp.permission_id
        WHERE ur.user_id = %s
          AND r.group_id = %s
          AND (
                (p.name = %s AND rp.value = TRUE)
                OR r.name = 'Manager'
              )
        LIMIT 1
    """, (user_id, group_id, permission_name))
    return cursor.fetchone() is not None


# Checks if a user is a member of a group
def is_group_member(user_id, group_id):
    cursor.execute("""
        SELECT 1 FROM group_member WHERE user_id = %s AND group_id = %s
    """, (user_id, group_id))
    return cursor.fetchone() is not None

# Gets user ID based on username from JWT identity
def get_current_user_id(identity):
    cursor.execute('SELECT id_registration FROM "user" WHERE username = %s', (identity,))
    result = cursor.fetchone()
    if result:
        return result["id_registration"]
    return None

# Loads specific key from a YAML file for Swagger documentation
def load_yaml(path, key):
    with open(path) as file:
        file_dict = yaml.safe_load(file)
        return file_dict[key]

# Syncs required permissions from JSON config to database
def sync_permissions():
    try:
        with open("config/permissions.json", "r") as f:
            required_permissions = json.load(f)

        with db.cursor() as cursor:
            sql_query = """
                INSERT INTO permission (name) VALUES (%s)
                ON CONFLICT (name) DO NOTHING
            """

            data_to_insert = []
            for p in required_permissions:
                data_to_insert.append((p,))

            cursor.executemany(sql_query, data_to_insert)
            db.commit()
    except Exception as e:
        db.rollback()
        print(f"Failed to sync permissions: {e}")

# Function below was generated using AI (ChatGPT)
# Validates if binary data represents a JPEG or PNG image
def is_valid_image(data: bytes) -> bool:
    if not isinstance(data, bytes) or len(data) < 8:
        return False
    # JPEG
    if data.startswith(b'\xff\xd8\xff'):
        return True
    # PNG
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        return True
    return False