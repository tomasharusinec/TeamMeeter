import os
import psycopg2
from dotenv import load_dotenv

def _migrate_activity_deadline_column(cursor, conn):
    cursor.execute("""
        SELECT data_type
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'activity'
          AND column_name = 'deadline'
    """)
    row = cursor.fetchone()
    if row is None:
        return

    current_type = row[0]
    if current_type == 'timestamp with time zone':
        return

    print("Migrating activity.deadline to TIMESTAMPTZ.")
    cursor.execute("""
        ALTER TABLE activity
        ALTER COLUMN deadline TYPE TIMESTAMPTZ
        USING CASE
            WHEN deadline IS NULL THEN NULL
            ELSE deadline::timestamp AT TIME ZONE 'UTC'
        END
    """)
    conn.commit()
    print("Migration finished: activity.deadline is TIMESTAMPTZ.")


def _migrate_activity_status_column(cursor, conn):
    cursor.execute("""
        SELECT data_type
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'activity'
          AND column_name = 'status'
    """)
    row = cursor.fetchone()
    if row is not None:
        # Column exists; still make sure no NULLs remain.
        cursor.execute("""
            UPDATE activity
            SET status = 'todo'
            WHERE status IS NULL
        """)
        conn.commit()
        return

    print("Adding activity.status column with default 'todo'.")
    cursor.execute("""
        ALTER TABLE activity
        ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'todo'
    """)
    conn.commit()
    print("Migration finished: activity.status added.")

def _migrate_group_capacity_column(cursor, conn):
    cursor.execute("""
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'group'
          AND column_name = 'capacity'
    """)
    row = cursor.fetchone()
    if row is not None:
        cursor.execute("""
            UPDATE "group"
            SET capacity = 10
            WHERE capacity IS NULL OR capacity < 1
        """)
        conn.commit()
        return

    print('Adding "group".capacity column with default 10.')
    cursor.execute("""
        ALTER TABLE "group"
        ADD COLUMN capacity INTEGER NOT NULL DEFAULT 10
    """)
    cursor.execute("""
        ALTER TABLE "group"
        ADD CONSTRAINT group_capacity_positive CHECK (capacity > 0)
    """)
    conn.commit()
    print('Migration finished: "group".capacity added.')

# This function was generated using AI (Gemini) with slight manual refinements
def init_db():
    """
    Initializes the PostgreSQL database for the TeamsMeeter application.
    Checks if the database 'TeamsMeeter' exists, creates it if not,
    and applies the schema from 'database.txt' if the database is empty.
    """
    load_dotenv()
    password = os.getenv("MY_PASS")
    
    if not password:
        print("Warning: MY_PASS environment variable not set. Connection might fail if password is required.")

    db_name = os.getenv("DB_NAME", "TeamsMeeter")
    host = os.getenv("DB_HOST", "localhost")
    port = os.getenv("DB_PORT", "5432")
    user = os.getenv("DB_USER", "postgres")
    
    try:
        print(f"Connecting to PostgreSQL server to check for database '{db_name}'.")
        conn = psycopg2.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database="postgres"
        )
        conn.autocommit = True
        cursor = conn.cursor()

        cursor.execute("SELECT 1 FROM pg_database WHERE datname = %s", (db_name,))
        exists = cursor.fetchone()
        
        if not exists:
            print(f"Creating database '{db_name}'.")
            cursor.execute(f"CREATE DATABASE \"{db_name}\"")
            print(f"Database '{db_name}' created successfully.")
        else:
            print(f"Database '{db_name}' already exists.")
            
        cursor.close()
        conn.close()

        print(f"Connecting to database '{db_name}' to check schema.")
        conn = psycopg2.connect(
            host=host,
            port=port,
            user=user,
            password=password,
            database=db_name
        )
        cursor = conn.cursor()
        cursor.execute("SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user')")
        tables_exist = cursor.fetchone()[0]
        
        if not tables_exist:
            print("Applying schema from database.txt.")
            try:
                script_dir = os.path.dirname(os.path.abspath(__file__))
                schema_path = os.path.join(script_dir, "database.txt")
                
                with open(schema_path, "r", encoding="utf-8") as f:
                    sql = f.read()
                    if sql.strip():
                        cursor.execute(sql)
                        conn.commit()
                        print("Schema applied successfully.")
                    else:
                        print("Warning: database.txt is empty.")
            except Exception as e:
                conn.rollback()
                print(f"Error applying schema: {e}")
                raise e
        else:
            print("Tables already exist. Skipping schema application.")

        try:
            _migrate_activity_deadline_column(cursor, conn)
            _migrate_activity_status_column(cursor, conn)
            _migrate_group_capacity_column(cursor, conn)
        except Exception as e:
            conn.rollback()
            print(f"Error applying migrations: {e}")
            raise e
            
        cursor.close()
        conn.close()
        print("Database initialization completed.")

    except Exception as e:
        print(f"An error occurred during database initialization: {e}")
