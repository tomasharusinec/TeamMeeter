import os
from dotenv import load_dotenv
import psycopg2
from psycopg2.extras import RealDictCursor

load_dotenv()
db = psycopg2.connect(host = "localhost", port = "5432", user = "postgres", password = os.getenv("MY_PASS"), database = "TeamsMeeter")
cursor = db.cursor(cursor_factory=RealDictCursor)

def get_current_user_id(identity):
    cursor.execute('SELECT id_registration FROM "user" WHERE username = %s', (identity,))
    result = cursor.fetchone()
    if result:
        return result["id_registration"]
    return None