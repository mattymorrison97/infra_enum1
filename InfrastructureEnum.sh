#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to install Go if not installed
install_go() {
    if ! command -v go &> /dev/null
    then
        echo -e "${RED}[!] Go not found. Installing Go...${NC}"
        wget https://dl.google.com/go/go1.16.5.linux-amd64.tar.gz
        sudo tar -C /usr/local -xzf go1.16.5.linux-amd64.tar.gz
        export PATH=$PATH:/usr/local/go/bin
    fi
}

# Function to install a Go-based tool
install_go_tool() {
    tool=$1
    repo=$2
    if ! command -v $tool &> /dev/null
    then
        echo -e "${GREEN}[+] Installing $tool...${NC}"
        go get -u $repo
    fi
}

# Install Go
install_go

# Install tools
install_go_tool assetfinder github.com/tomnomnom/assetfinder
install_go_tool httprobe github.com/tomnomnom/httprobe
install_go_tool gowitness github.com/sensepost/gowitness

# Install testssl.sh
if [ ! -d "/opt/testssl.sh" ]; then
    echo -e "${GREEN}[+] Installing testssl.sh...${NC}"
    git clone --depth 1 https://github.com/drwetter/testssl.sh.git /opt/testssl.sh
fi

# Install nmap
if ! command -v nmap &> /dev/null
then
    echo -e "${GREEN}[+] Installing nmap...${NC}"
    sudo apt-get update
    sudo apt-get install -y nmap
fi

# Input URL
url=$1

# Create necessary directories
if [ ! -d "$url" ]; then
    mkdir -p "$url/recon/scans"
    mkdir -p "$url/recon/httprobe"
    mkdir -p "$url/recon/tls"
    mkdir -p "$url/recon/screenshots"
fi

# Ensure necessary files exist
touch "$url/recon/httprobe/alive.txt"
touch "$url/recon/final.txt"

# Harvesting subdomains with assetfinder
echo -e "${GREEN}[+] Harvesting subdomains with assetfinder...${NC}"
assetfinder $url >> "$url/recon/assets.txt"
grep "$url" "$url/recon/assets.txt" >> "$url/recon/final.txt"
rm "$url/recon/assets.txt"

# Probing for alive domains
echo -e "${GREEN}[+] Probing for alive domains...${NC}"
sort -u "$url/recon/final.txt" | httprobe -s -p https:443 | sed 's/https\?:\/\///' | tr -d ':443' >> "$url/recon/httprobe/a.txt"
sort -u "$url/recon/httprobe/a.txt" > "$url/recon/httprobe/alive.txt"
rm "$url/recon/httprobe/a.txt"

# TLS configuration checks using testssl.sh
echo -e "${GREEN}[+] Checking TLS configuration...${NC}"
for domain in $(cat "$url/recon/httprobe/alive.txt"); do
    /opt/testssl.sh/testssl.sh --quiet --warnings batch --htmlfile "$url/recon/tls/$domain.html" $domain &> /dev/null &
done

# Wait for all background jobs to complete
wait
echo -e "${GREEN}[+] TLS checks completed and saved in ${YELLOW}$url/recon/tls${NC}"

# Scanning for open ports
echo -e "${GREEN}[+] Scanning for open ports on the live hosts...${NC}"
nmap -iL "$url/recon/httprobe/alive.txt" -T4 -A -oA "$url/recon/scans/scanned" > "$url/recon/scans/scanned.txt" 2>&1 &
nmap_pid=$!

# Wait for the Nmap scan to complete
wait $nmap_pid
echo -e "${GREEN}[+] Nmap scan completed and saved in ${YELLOW}$url/recon/scans${NC}"

# Capture screenshots of live subdomains using gowitness
echo -e "${GREEN}[+] Capturing screenshots of live subdomains...${NC}"
gowitness file -f "$url/recon/httprobe/alive.txt" -P "$url/recon/screenshots"
echo -e "${GREEN}[+] Screenshots captured and saved in ${YELLOW}$url/recon/screenshots${NC}"
