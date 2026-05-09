from flask import Flask, jsonify
import os, time

app = Flask(__name__)
START = time.time()

@app.route("/")
def index():
    return jsonify({
        "env": os.environ.get("ENV_ID", "unknown"),
        "name": os.environ.get("ENV_NAME", "unnamed"),
        "uptime": round(time.time() - START, 2)
    })

@app.route("/health")
def health():
    return jsonify({"status": "ok", "uptime": round(time.time() - START, 2)})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
