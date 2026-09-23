import sqlite3
import csv
import io
from datetime import datetime
from flask import Flask, render_template_string, request, redirect, url_for, flash, session, jsonify

app = Flask(__name__)
app.secret_key = "kiosk_secret_key_2026"
DB_NAME = "kiosk_system.db"

# ------------------------------------------------------------------------------
# ADVANCED CORS & PREFLIGHT HANDLING (Fixes Mobile App Network Blocking)
# ------------------------------------------------------------------------------
@app.before_request
def handle_preflight():
    if request.method == "OPTIONS":
        response = app.make_default_options_response()
        response.headers['Access-Control-Allow-Origin'] = '*'
        response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, X-Requested-With'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
        return response, 200

@app.after_request
def add_cors_headers(response):
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, X-Requested-With'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    return response

# ------------------------------------------------------------------------------
# DATABASE SETUP & INITIALIZATION
# ------------------------------------------------------------------------------
def get_db():
    conn = sqlite3.connect(DB_NAME)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    cursor = conn.cursor()

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            student_id TEXT UNIQUE NOT NULL,
            rfid_number TEXT UNIQUE NOT NULL,
            points INTEGER DEFAULT 0
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            stock INTEGER NOT NULL,
            status TEXT NOT NULL,
            last_updated TEXT NOT NULL
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS rewards (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            points_required INTEGER NOT NULL,
            availability TEXT NOT NULL
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            rfid_number TEXT NOT NULL,
            transaction_date TEXT NOT NULL,
            amount REAL NOT NULL,
            points_earned INTEGER NOT NULL
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS admin_users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            role TEXT NOT NULL
        )
    ''')

    cursor.execute('''
        CREATE TABLE IF NOT EXISTS store_settings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_name TEXT NOT NULL,
            is_active INTEGER DEFAULT 1,
            created_at TEXT NOT NULL
        )
    ''')

    # Seed Store Settings if empty
    cursor.execute("SELECT COUNT(*) FROM store_settings")
    if cursor.fetchone()[0] == 0:
        cursor.execute("INSERT INTO store_settings (store_name, created_at) VALUES (?, ?)",
                       ("PCU Main Store", datetime.now().strftime("%Y-%m-%d %H:%M")))

    # Seed Admin Users if empty
    cursor.execute("SELECT COUNT(*) FROM admin_users")
    if cursor.fetchone()[0] == 0:
        cursor.executemany('''
            INSERT INTO admin_users (username, password, role)
            VALUES (?, ?, ?)
        ''', [
            ("admin", "admin123", "Delete"),
            ("editor_admin", "admin123", "Edit"),
            ("viewer_admin", "admin123", "View")
        ])

    # Seed Initial Data if empty
    cursor.execute("SELECT COUNT(*) FROM customers")
    if cursor.fetchone()[0] == 0:
        cursor.executemany('''
            INSERT INTO customers (name, student_id, rfid_number, points)
            VALUES (?, ?, ?, ?)
        ''', [
            ("Alexondre Violado", "2024-0001", "RFID-1001", 120),
            ("Hussein Buarki", "2024-0002", "RFID-1002", 45),
            ("Calvin Castro", "2024-0003", "RFID-1003", 210)
        ])

        cursor.executemany('''
            INSERT INTO products (name, price, stock, status, last_updated)
            VALUES (?, ?, ?, ?, ?)
        ''', [
            ("Bottled Water", 15.00, 50, "Available", "2026-03-08 08:00 AM"),
            ("Fruit Juice", 30.00, 4, "Low Stock", "2026-03-08 09:30 AM"),
            ("Club Sandwich", 60.00, 15, "Available", "2026-03-08 10:15 AM"),
            ("Chocolate Cookie", 25.00, 0, "Out of Stock", "2026-03-08 11:00 AM")
        ])

        cursor.executemany('''
            INSERT INTO rewards (name, points_required, availability)
            VALUES (?, ?, ?)
        ''', [
            ("Free Drink", 50, "Available"),
            ("₱20 Discount", 100, "Available"),
            ("Free Snack", 150, "Available")
        ])

        cursor.executemany('''
            INSERT INTO transactions (rfid_number, transaction_date, amount, points_earned)
            VALUES (?, ?, ?, ?)
        ''', [
            ("RFID-1001", "2026-03-01 10:30", 500.00, 50),
            ("RFID-1001", "2026-03-05 14:15", 700.00, 70),
            ("RFID-1002", "2026-03-06 11:00", 450.00, 45),
            ("RFID-1003", "2026-03-07 16:45", 2100.00, 210)
        ])

    conn.commit()
    conn.close()

init_db()

# ------------------------------------------------------------------------------
# JSON REST API ENDPOINTS FOR MOBILE APP
# ------------------------------------------------------------------------------

# Route aliases to handle all common endpoint paths requested by mobile apps
@app.route("/api/menu", methods=["GET", "OPTIONS"])
@app.route("/menu", methods=["GET", "OPTIONS"])
@app.route("/api/products", methods=["GET", "OPTIONS"])
@app.route("/products", methods=["GET", "OPTIONS"])
def api_get_products():
    conn = get_db()
    products = conn.execute("SELECT * FROM products").fetchall()
    conn.close()
    
    # Return formatted JSON list
    return jsonify([dict(product) for product in products]), 200


@app.route("/api/customer/<rfid>", methods=["GET", "OPTIONS"])
@app.route("/customer/<rfid>", methods=["GET", "OPTIONS"])
def api_get_customer(rfid):
    conn = get_db()
    customer = conn.execute("SELECT * FROM customers WHERE rfid_number = ? OR student_id = ?", (rfid, rfid)).fetchone()
    conn.close()
    
    if customer:
        return jsonify(dict(customer)), 200
    return jsonify({"error": "Customer not found"}), 404


@app.route("/api/redeem", methods=["POST", "OPTIONS"])
def api_redeem():
    data = request.get_json() or {}
    rfid_number = data.get("rfid_number")
    product_id = data.get("product_id")

    if not rfid_number or not product_id:
        return jsonify({"error": "Missing rfid_number or product_id."}), 400

    conn = get_db()
    cursor = conn.cursor()

    customer = cursor.execute("SELECT * FROM customers WHERE rfid_number = ?", (rfid_number,)).fetchone()
    if not customer:
        conn.close()
        return jsonify({"error": "RFID card not registered."}), 404

    product = cursor.execute("SELECT * FROM products WHERE id = ?", (product_id,)).fetchone()
    if not product:
        conn.close()
        return jsonify({"error": "Product not found."}), 404

    if product['stock'] <= 0:
        conn.close()
        return jsonify({"error": "Product is out of stock."}), 400

    points_required = int(product['price'])
    if customer['points'] < points_required:
        conn.close()
        return jsonify({"error": f"Insufficient points balance. Required: {points_required}"}), 400

    new_points = customer['points'] - points_required
    new_stock = product['stock'] - 1
    new_status = "Available" if new_stock > 10 else ("Low Stock" if new_stock > 0 else "Out of Stock")
    now = datetime.now().strftime("%Y-%m-%d %I:%M %p")

    cursor.execute("UPDATE customers SET points = ? WHERE id = ?", (new_points, customer['id']))
    cursor.execute("UPDATE products SET stock = ?, status = ?, last_updated = ? WHERE id = ?", (new_stock, new_status, now, product['id']))
    cursor.execute("INSERT INTO transactions (rfid_number, transaction_date, amount, points_earned) VALUES (?, ?, ?, ?)",
                   (rfid_number, now, 0, -points_required))

    conn.commit()
    conn.close()

    return jsonify({
        "message": f"Successfully redeemed {product['name']}!",
        "remaining_points": new_points,
        "remaining_stock": new_stock
    }), 200

# ------------------------------------------------------------------------------
# WEB ADMIN INTERFACE TEMPLATES & ROUTES
# ------------------------------------------------------------------------------

HTML_BASE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Kiosk Admin System</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background-color: #f4f6f9; margin: 0; padding: 20px; color: #333; }
        .container { max-width: 1000px; margin: 0 auto; background: #fff; padding: 20px 30px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        nav { background: #1e293b; padding: 12px 20px; border-radius: 6px; margin-bottom: 20px; display: flex; gap: 15px; }
        nav a { color: #f8fafc; text-decoration: none; font-weight: bold; }
        nav a:hover { text-decoration: underline; }
        table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        th, td { border: 1px solid #e2e8f0; padding: 10px 12px; text-align: left; }
        th { background: #f1f5f9; }
        .badge-available { background: #dcfce7; color: #166534; padding: 3px 8px; border-radius: 4px; font-size: 12px; }
        .badge-low { background: #fef9c3; color: #854d0e; padding: 3px 8px; border-radius: 4px; font-size: 12px; }
        .badge-out { background: #fee2e2; color: #991b1b; padding: 3px 8px; border-radius: 4px; font-size: 12px; }
        .btn { background: #2563eb; color: #fff; border: none; padding: 8px 14px; border-radius: 4px; cursor: pointer; text-decoration: none; display: inline-block; }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input[type="text"], input[type="password"] { width: 100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
        .flash { padding: 10px; background: #d1e7dd; color: #0f5132; border-radius: 4px; margin-bottom: 15px; }
    </style>
</head>
<body>
    <div class="container">
        {% if session.get('user') %}
        <nav>
            <a href="{{ url_for('dashboard') }}">Dashboard</a>
            <a href="{{ url_for('inventory') }}">Inventory</a>
            <a href="{{ url_for('customers') }}">Customers</a>
            <a href="{{ url_for('transactions') }}">Transactions</a>
            <a href="{{ url_for('logout') }}" style="margin-left: auto; color: #fca5a5;">Logout ({{ session['user'] }})</a>
        </nav>
        {% endif %}

        {% with messages = get_flashed_messages() %}
          {% if messages %}
            {% for message in messages %}
              <div class="flash">{{ message }}</div>
            {% endfor %}
          {% endif %}
        {% endwith %}

        {% block content %}{% endblock %}
    </div>
</body>
</html>
"""

@app.route("/")
def index():
    if "user" in session:
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username")
        password = request.form.get("password")
        conn = get_db()
        user = conn.execute("SELECT * FROM admin_users WHERE username = ? AND password = ?", (username, password)).fetchone()
        conn.close()
        if user:
            session["user"] = user["username"]
            session["role"] = user["role"]
            return redirect(url_for("dashboard"))
        flash("Invalid username or password.")
    
    login_html = HTML_BASE + """
    {% block content %}
    <h2>Admin Login</h2>
    <form method="POST">
        <div class="form-group">
            <label>Username</label>
            <input type="text" name="username" required>
        </div>
        <div class="form-group">
            <label>Password</label>
            <input type="password" name="password" required>
        </div>
        <button type="submit" class="btn">Login</button>
    </form>
    {% endblock %}
    """
    return render_template_string(login_html)

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

@app.route("/dashboard")
def dashboard():
    if "user" not in session:
        return redirect(url_for("login"))
    
    conn = get_db()
    total_products = conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    total_customers = conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
    total_transactions = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
    conn.close()

    dash_html = HTML_BASE + """
    {% block content %}
    <h2>Dashboard Overview</h2>
    <div style="display: flex; gap: 20px; margin-top: 20px;">
        <div style="flex: 1; background: #eff6ff; padding: 20px; border-radius: 6px; text-align: center;">
            <h3>Total Products</h3>
            <p style="font-size: 28px; font-weight: bold; margin: 0;">{{ total_products }}</p>
        </div>
        <div style="flex: 1; background: #f0fdf4; padding: 20px; border-radius: 6px; text-align: center;">
            <h3>Registered Customers</h3>
            <p style="font-size: 28px; font-weight: bold; margin: 0;">{{ total_customers }}</p>
        </div>
        <div style="flex: 1; background: #fefce8; padding: 20px; border-radius: 6px; text-align: center;">
            <h3>Transactions Logged</h3>
            <p style="font-size: 28px; font-weight: bold; margin: 0;">{{ total_transactions }}</p>
        </div>
    </div>
    {% endblock %}
    """
    return render_template_string(dash_html, total_products=total_products, total_customers=total_customers, total_transactions=total_transactions)

@app.route("/inventory")
def inventory():
    if "user" not in session:
        return redirect(url_for("login"))
    conn = get_db()
    products = conn.execute("SELECT * FROM products").fetchall()
    conn.close()

    inv_html = HTML_BASE + """
    {% block content %}
    <h2>Product Inventory</h2>
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Name</th>
                <th>Price</th>
                <th>Stock</th>
                <th>Status</th>
                <th>Last Updated</th>
            </tr>
        </thead>
        <tbody>
            {% for p in products %}
            <tr>
                <td>{{ p.id }}</td>
                <td>{{ p.name }}</td>
                <td>₱{{ "%.2f"|format(p.price) }}</td>
                <td>{{ p.stock }}</td>
                <td>
                    <span class="badge-{% if p.status == 'Available' %}available{% elif p.status == 'Low Stock' %}low{% else %}out{% endif %}">
                        {{ p.status }}
                    </span>
                </td>
                <td>{{ p.last_updated }}</td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
    {% endblock %}
    """
    return render_template_string(inv_html, products=products)

@app.route("/customers")
def customers():
    if "user" not in session:
        return redirect(url_for("login"))
    conn = get_db()
    customers_list = conn.execute("SELECT * FROM customers").fetchall()
    conn.close()

    cust_html = HTML_BASE + """
    {% block content %}
    <h2>Registered Customers</h2>
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Name</th>
                <th>Student ID</th>
                <th>RFID Tag</th>
                <th>Points Balance</th>
            </tr>
        </thead>
        <tbody>
            {% for c in customers_list %}
            <tr>
                <td>{{ c.id }}</td>
                <td>{{ c.name }}</td>
                <td>{{ c.student_id }}</td>
                <td><code>{{ c.rfid_number }}</code></td>
                <td><strong>{{ c.points }} pts</strong></td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
    {% endblock %}
    """
    return render_template_string(cust_html, customers_list=customers_list)

@app.route("/transactions")
def transactions():
    if "user" not in session:
        return redirect(url_for("login"))
    conn = get_db()
    txns = conn.execute("SELECT * FROM transactions ORDER BY id DESC").fetchall()
    conn.close()

    tx_html = HTML_BASE + """
    {% block content %}
    <h2>Transaction History</h2>
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>RFID Tag</th>
                <th>Date & Time</th>
                <th>Amount</th>
                <th>Points Changed</th>
            </tr>
        </thead>
        <tbody>
            {% for t in txns %}
            <tr>
                <td>{{ t.id }}</td>
                <td><code>{{ t.rfid_number }}</code></td>
                <td>{{ t.transaction_date }}</td>
                <td>₱{{ "%.2f"|format(t.amount) }}</td>
                <td style="color: {% if t.points_earned < 0 %}#dc2626{% else %}#16a34a{% endif %}; font-weight: bold;">
                    {{ t.points_earned }}
                </td>
            </tr>
            {% endfor %}
        </tbody>
    </table>
    {% endblock %}
    """
    return render_template_string(tx_html, txns=txns)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
