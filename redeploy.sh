#!/bin/bash
# Quick redeploy script - keeps existing secret, restarts containers
# Use this for config changes (nginx, etc.)

cd "$(dirname "$0")"

echo "n" | ./deploy-secure.sh
