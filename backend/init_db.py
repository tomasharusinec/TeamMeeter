import os
import psycopg2
from dotenv import load_dotenv

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
            
        cursor.close()
        conn.close()
        print("Database initialization completed.")

    except Exception as e:
        print(f"An error occurred during database initialization: {e}")
