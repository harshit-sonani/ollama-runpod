#!/bin/bash

# Ollama Installation and Setup Script
# This script installs Ollama, pulls the glm-4.7-flash model, and configures it for public access
# Compatible with Docker/container environments

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root (warning only for Docker containers)
if [ "$(id -u)" -eq 0 ]; then
    print_warning "Running as root. This is typical for container/Docker environments."
    print_warning "Continuing setup in container environment..."
fi

# Step 0: Detect IP address
print_step "Step 0: Detecting instance IP address..."
DETECTED_IP=""

# Try different methods to find IP
if command -v ip &> /dev/null; then
    DETECTED_IP=$(ip addr show 2>/dev/null | grep -E 'inet (192|10|172|172.1[0-9]|172.2[0-9]|172.3[0-9]|127)' | grep -v 127.0.0.1| awk '{print $2}' | cut -d'/' -f1 | head -1)
fi

if [ -z "$DETECTED_IP" ] && command -v hostname &> /dev/null; then
    DETECTED_IP=$(hostname -I | awk '{print $1}')
fi

if [ -z "$DETECTED_IP" ]; then
    DETECTED_IP="localhost"
fi

print_info "Detected IP: ${DETECTED_IP}"

# Step 1: Install Ollama
print_step "Step 1: Installing Ollama..."
if ! command -v ollama &> /dev/null; then
    print_info "Downloading and installing Ollama..."

    # Create a temporary directory for installation
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # Download the installation script
    curl -fsSL https://ollama.com/install.sh | sh

    # Clean up
    cd /
    rm -rf "$TEMP_DIR"

    print_info "Ollama installed successfully!"
else
    print_info "Ollama is already installed."
    OLLAMA_VERSION=$(ollama --version 2>/dev/null || echo "unknown")
    print_info "Ollama version: $OLLAMA_VERSION"
fi

# Step 2: Pull glm-4.7-flash model
print_step "Step 2: Pulling glm-4.7-flash model..."
if ! ollama list 2>/dev/null | grep -q "glm-4.7-flash"; then
    print_info "Downloading model..."
    ollama pull glm-4.7-flash
    print_info "Model downloaded successfully!"
else
    print_info "Model glm-4.7-flash is already downloaded."
fi

# Step 3: Configure Ollama for public access
print_step "Step 3: Configuring Ollama for public access..."

# Kill any existing ollama processes
print_info "Stopping any existing Ollama processes..."
pkill -f "ollama serve" 2>/dev/null || true
sleep 1

# Start Ollama in background with public access
print_info "Starting Ollama server..."
nohup ollama serve --host 0.0.0.0:11434 > /tmp/ollama.log 2>&1 &
OLLAMA_PID=$!

# Wait for Ollama to start
print_info "Waiting for Ollama to start..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        print_info "Ollama is running!"
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

# Step 4: Verify connection
print_step "Step 4: Verifying connection..."
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    print_info "Ollama is accessible on localhost:11434"
else
    print_error "Failed to connect to Ollama"
    print_info "Checking logs: tail -n 50 /tmp/ollama.log"
    tail -n 50 /tmp/ollama.log
    exit 1
fi

# Step 5: Check models
print_step "Step 5: Checking available models..."
curl -s http://localhost:11434/api/tags | python3 -m json.tool 2>/dev/null || curl -s http://localhost:11434/api/tags

# Step 6: Save configuration for easy access
print_step "Step 6: Saving configuration..."

# Create a configuration file with all the needed info
cat > /tmp/ollama-config.txt << EOF
===================================
Ollama Configuration Summary
===================================
Installed: Yes
Version: $(ollama --version 2>/dev/null || echo "unknown")
IP Address: ${DETECTED_IP}
Port: 11434
Model: glm-4.7-flash

===================================
Access Information
===================================
Local Access: http://localhost:11434
Container IP: http://${DETECTED_IP}:11434

===================================
Sample Curl Commands
===================================

# Test basic connection:
curl http://localhost:11434/api/tags

# List all models:
curl http://localhost:11434/api/tags | python3 -m json.tool

# Send a chat completion request:
curl http://localhost:11434/api/chat \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "glm-4.7-flash",
    "messages": [{"role": "user", "content": "Hello! Please introduce yourself."}],
    "stream": false
  }'

# Run a specific model interactively:
curl http://localhost:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "glm-4.7-flash",
    "prompt": "What is the capital of France?",
    "stream": false
  }'

# Test streaming response:
curl http://localhost:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "glm-4.7-flash",
    "prompt": "Count from 1 to 10",
    "stream": true
  }'

# Get model details:
curl http://localhost:11434/api/tags | python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps([m['name'] for min data['models']], indent=2))"

===================================
Useful Commands
===================================
# Check if Ollama is running:
ps aux | grep ollama | grep -v grep

# View logs:
tail -f /tmp/ollama.log

# List installed models:
ollama list

# Pull a new model:
ollama pull <model-name>

# Stop Ollama:
pkill -f "ollama serve"

# Restart Ollama:
pkill -f "ollama serve" && sleep 2 && nohup ollama serve --host 0.0.0.0:11434 > /tmp/ollama.log 2>&1 &

===================================
EOF

# Display the configuration
echo ""
cat /tmp/ollama-config.txt

# Step 7: Display sample curl commands
print_step "Step 7: Quick Test Commands"
echo ""
echo "Try these commands:"
echo ""
echo "1. Test basic connection:"
echo "   curl http://${DETECTED_IP}:11434/api/tags"
echo ""
echo "2. Send a chat request:"
echo "   curl http://${DETECTED_IP}:11434/api/chat \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"model\":\"glm-4.7-flash\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"stream\":false}'"
echo ""
echo "3. List all models:"
echo "   curl http://${DETECTED_IP}:11434/api/tags | python3 -m json.tool"
echo ""
echo "4. Run the model interactively:"
echo "   curl http://${DETECTED_IP}:11434/api/generate \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"model\":\"glm-4.7-flash\",\"prompt\":\"Tell me a joke\",\"stream\":false}'"
echo ""

# Step 8: Provide security warnings
echo ""
print_warning "Security Recommendations:"
echo "  - Add authentication (see: https://github.com/ollama/ollama#authentication)"
echo "  - Configure firewall to only allow trusted IPs"
echo "  - Use a reverse proxy with SSL/TLS for production"
echo "  - Consider using Docker port mapping: -p 11434:11434"
echo ""

print_info "Setup Complete!"
print_info "Ollama is now running on ${DETECTED_IP}:11434"
print_info "You can access it from another machine using the IP above.