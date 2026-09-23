from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)
DATABASE = 'database.db'

def get_db():
    conn = sqlite3.connect(DATABASE)
    conn.row_factory = sqlite3.Row
    return conn

# Init DB helper
def init_db():
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id TEXT,
            name TEXT,
            rfid_number TEXT UNIQUE,
            points INTEGER DEFAULT 0
        )
    ''')
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            price INTEGER
        )
    ''')
    conn.commit()
    conn.close()

# Execute database setup on launch
try:
    init_db()
except Exception as e:
    print(f"Database init note: {e}")

@app.route("/")
def home():
    return "PCU Kiosk & Rewards API Server is Running!"

# ==============================================================================
# PROCEDURE 2: MOBILE APP API ENDPOINTS
# ==============================================================================

@app.route("/api/products", methods=["GET"])
def api_get_products():
    """Returns all products in JSON format for the mobile app UI."""
    try:
        conn = get_db()
        products = conn.execute("SELECT * FROM products").fetchall()
        conn.close()
        return jsonify([dict(p) for p in products]), 200
    except Exception as e:
        return jsonify([]), 200

@app.route("/api/mobile-login", methods=["POST"])
def api_mobile_login():
    """Verifies scanned NFC/RFID tag against customer database."""
    data = request.get_json() or {}
    rfid_number = data.get("rfid_number", "").strip()
    
    try:
        conn = get_db()
        customer = conn.execute(
            "SELECT * FROM customers WHERE rfid_number = ?", 
            (rfid_number,)
        ).fetchone()
        conn.close()
        
        if customer:
            return jsonify({
                "success": True,
                "customer": dict(customer)
            }), 200
        else:
            return jsonify({
                "success": False,
                "error": f"Card ID '{rfid_number}' is not registered."
            }), 404
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True)
