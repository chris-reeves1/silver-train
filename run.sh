#!/bin/bash
exec python -m gunicorn -b 0.0.0.0:5500 app:app
