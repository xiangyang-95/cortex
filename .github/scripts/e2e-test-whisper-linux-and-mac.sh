#!/bin/bash

## Example run command
# ./linux-and-mac.sh './jan/plugins/@janhq/inference-plugin/dist/nitro/nitro_mac_arm64' https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v0.3-GGUF/resolve/main/tinyllama-1.1b-chat-v0.3.Q2_K.gguf

# Check for required arguments
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <path_to_binary> <url_to_download>"
    exit 1
fi

rm /tmp/response1.log /tmp/response2.log /tmp/nitro.log

BINARY_PATH=$1
DOWNLOAD_URL=$2

# Random port to ensure it's not used
min=10000
max=11000
range=$((max - min + 1))
PORT=$((RANDOM % range + min))

# Start the binary file
"$BINARY_PATH" 1 127.0.0.1 $PORT >/tmp/nitro.log &

# Get the process id of the binary file
pid=$!

if ! ps -p $pid >/dev/null; then
    echo "nitro failed to start. Logs:"
    cat /tmp/nitro.log
    exit 1
fi

# Wait for a few seconds to let the server start
sleep 5

# Check if /tmp/testwhisper exists, if not, download it
if [[ ! -f "/tmp/testwhisper" ]]; then
    curl --connect-timeout 300 $DOWNLOAD_URL --output /tmp/testwhisper
fi

# Run the curl commands
response1=$(curl --connect-timeout 60 -o /tmp/response1.log -s -w "%{http_code}" --location "http://127.0.0.1:$PORT/v1/audio/load_model" \
    --header 'Content-Type: application/json' \
    --data '{
    "model_path": "/tmp/testwhisper",
    "model_id": "whisper.cpp",
    "openvino_encode_device": "GPU",
}')

response2=$(
    curl --connect-timeout 60 -o /tmp/response2.log -s -w "%{http_code}" --location "http://127.0.0.1:$PORT/v1/audio/transcriptions" \
        --header 'Access-Control-Allow-Origin: *' \
        --form 'file=@"../whisper.cpp/samples/jfk.wav"' \
        --form 'model_id="whisper.cpp"' \
        --form 'temperature="0.0"' \
        --form 'prompt="The transcript is about OpenAI which makes technology like DALL·E, GPT-3, and ChatGPT with the hope of one day building an AGI system that benefits all of humanity. The president is trying to raly people to support the cause."' \
       
)

error_occurred=0
if [[ "$response1" -ne 200 ]]; then
    echo "The first curl command failed with status code: $response1"
    cat /tmp/response1.log
    error_occurred=1
fi

if [[ "$response2" -ne 200 ]]; then
    echo "The second curl command failed with status code: $response2"
    cat /tmp/response2.log
    error_occurred=1
fi

if [[ "$error_occurred" -eq 1 ]]; then
    echo "Nitro test run failed!!!!!!!!!!!!!!!!!!!!!!"
    echo "Nitro Error Logs:"
    cat /tmp/nitro.log
    kill $pid
    exit 1
fi

echo "----------------------"
echo "Log load model:"
cat /tmp/response1.log

echo "----------------------"
echo "Log run test:"
cat /tmp/response2.log

echo "Nitro test run successfully!"

# Kill the server process
kill $pid
