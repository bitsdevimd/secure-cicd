from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "secure-app"}), 200

@app.route('/ready')
def ready():
    return jsonify({"status": "ready", "service": "secure-app"}), 200

@app.route('/')
def home():
    return jsonify({
        "message": "Secure CI/CD Pipeline Demo",
        "version": os.getenv("APP_ENV", "local"),
        "security": "Kyverno + Trivy + Gitleaks enforced"
    }), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
