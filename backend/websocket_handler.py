import json
import os
import threading
import jwt
import psycopg2
from psycopg2.extras import RealDictCursor
from flask_sock import Sock
from cryptography.fernet import Fernet
from dotenv import load_dotenv

load_dotenv()
cipher_suite = Fernet(os.getenv("MESSAGE_ENCRYPTION_KEY"))
JWT_SECRET = os.getenv("JWT_SECRET_KEY")

connected_clients: dict[int, set] = {} # AI generated
clients_lock = threading.Lock() # AI generated
sock = Sock()

# Function below was generated using
# Registers new websocket connection for an authenticated user
def register(user_id: int, ws):
    with clients_lock:
        if user_id not in connected_clients:
            connected_clients[user_id] = set()
        connected_clients[user_id].add(ws)

# Function below was generated using AI
# Removes terminated websocket connection from active clients
def unregister(user_id: int, ws):
    with clients_lock:
        sockets = connected_clients.get(user_id)
        if sockets:
            sockets.discard(ws)
            if not sockets:
                del connected_clients[user_id]