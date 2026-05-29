from flask import Flask, jsonify
from os import getenv

app = Flask(__name__)

@app.route('/')
def home():
    hostname = getenv('HOSTNAME')
    name = getenv('YOUR_NAME')
    if name is None:
        name = "friend"
    return f"<h1>Hello {name}.</h1>\n\n<h2>I'm currently running in {hostname}.</h2>\n"

@app.route("/health")
def health():
    return jsonify(status="ok"), 200
