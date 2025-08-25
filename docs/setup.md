# 🚀 Complete Setup Guide

**Get started with the ATAK VNS Offline Routing Generator from scratch.**

## 📋 What You Need

### Your Computer
- **Windows 10+**, **macOS 10.15+**, or **Linux**
- **8GB RAM** (minimum 4GB, but 8GB+ recommended for best performance)
- **20GB free storage space** (for downloads and generated files)
- **Internet connection** (for downloading Docker, maps, and updates)

### Required Software
- **Docker** - This is the only thing you need to install

## 🐳 Step 1: Install Docker

Docker is like a virtual computer that runs our mapping software. It keeps everything organized and working the same way on any computer.

### Windows Users
1. Go to [docker.com/get-started](https://docker.com/get-started)
2. Click **"Download Docker Desktop"**
3. Run the installer (it's about 500MB)
4. **Restart your computer** when it asks
5. Open Docker Desktop from your desktop
6. Wait for it to say "Engine running" in the bottom left

### Mac Users  
1. Go to [docker.com/get-started](https://docker.com/get-started)
2. Click **"Download Docker Desktop"**
3. Drag Docker to your Applications folder
4. Open Docker from Applications
5. Enter your password when it asks (this is normal)
6. Wait for the whale icon to appear in your top menu bar

### Linux Users
Open your terminal and type:
```bash
# For Ubuntu/Debian:
sudo apt update
sudo apt install docker.io

# Start Docker
sudo systemctl start docker
sudo systemctl enable docker

# Add yourself to docker group (so you don't need sudo)
sudo usermod -aG docker $USER
```
**Log out and back in** after the last command.

### ✅ Test Docker Installation
Open your terminal/command prompt and type:
```bash
docker --version
```
You should see something like: `Docker version 20.10.x`

## 📁 Step 2: Get the Generator

You can get this tool in two ways:

### 🔽 Easy Way (Download ZIP)
1. Go to https://github.com/joshuafuller/atak-vns-offline-routing-generator
2. Click the green **"Code"** button
3. Click **"Download ZIP"**
4. Extract the ZIP file to a folder like:
   - Windows: `C:\Users\YourName\atak-vns-generator\`
   - Mac: `/Users/YourName/atak-vns-generator/`
   - Linux: `/home/yourname/atak-vns-generator/`

### 🔧 Advanced Way (Git Clone)
If you're comfortable with Git:
```bash
git clone https://github.com/joshuafuller/atak-vns-offline-routing-generator
cd atak-vns-offline-routing-generator
```

## ⚙️ Step 3: Prepare the Scripts

### Windows Users
1. Open the folder where you extracted the files
2. **Right-click in the folder** and choose **"Open in Terminal"** or **"Git Bash here"**
3. Type: `ls` and press Enter
   - You should see files like `run.sh`, `README.md`

### Mac/Linux Users
1. Open Terminal
2. Navigate to your folder:
   ```bash
   cd /path/to/your/atak-vns-generator
   ```
3. Make the script executable:
   ```bash
   chmod +x run.sh
   chmod +x list-regions.sh
   ```
4. Test by typing: `ls -la *.sh`
   - You should see `run.sh` and `list-regions.sh` with execute permissions

## 🗺️ Step 4: Your First Routing Data

Let's test everything by creating routing data for Delaware (it's small and fast):

### Run Your First Generation
```bash
./run.sh delaware
```

**What happens:**
1. ✅ Docker downloads our pre-built image (first time only, ~500MB)
2. ✅ Downloads Delaware map data (~20MB)
3. ✅ Processes the data (about 30 seconds)
4. ✅ Creates your routing files

**You should see:**
```
🔍 Checking for pre-built image...
✅ Using pre-built image: ghcr.io/joshuafuller/atak-vns-offline-routing-generator:latest
🌍 Generating offline routing data for: delaware
📥 Downloading delaware OSM data...
⚙️  Processing with GraphHopper...
📦 Packaging data for VNS...
✅ Success! Generated: ./output/delaware/
📦 ZIP created: ./output/delaware.zip (9.1 MB)
```

## ✅ Step 5: Verify Everything Works

Check your files:
```bash
# List what was created
ls output/

# Should show:
# delaware/        (folder with routing data)
# delaware.zip     (compressed file for your device)
```

Check the routing folder:
```bash
ls output/delaware/

# Should show files like:
# delaware.kml  delaware.poly  edges  geometry  nodes  etc.
```

## 🎯 What's Next?

### Generate Your Region
```bash
# See all available regions
./list-regions.sh

# Generate your state (examples)
./run.sh california
./run.sh texas  
./run.sh great-britain
```

### Install on Your Android Device
1. **Copy** `output/delaware.zip` to your Android device
2. **Extract** the ZIP file
3. **Copy** the `delaware/` folder to:
   ```
   Internal Storage/atak/tools/VNS/GH/delaware/
   ```
4. **Restart ATAK** - VNS will detect the new routing data

## 🐛 Common Issues

### "Docker not found"
- **Windows**: Make sure Docker Desktop is running (look for whale icon in system tray)
- **Mac**: Make sure Docker Desktop is running (whale in menu bar)
- **Linux**: Run `sudo systemctl start docker`

### "Permission denied" 
- **Windows**: Try running Command Prompt "As Administrator"
- **Mac/Linux**: Make sure you ran `chmod +x run.sh`

### "Out of memory"
- Close other programs
- Try a smaller region first (Delaware, Rhode Island)
- Large states like California need 8GB+ RAM

### Downloads fail
- Check your internet connection
- Try again in a few minutes (Geofabrik servers may be busy)
- Verify the region name: use `./list-regions.sh`

## 🆘 Getting Help

**Something not working?**
1. **Try Delaware first** - it's small and downloads quickly
2. **Copy the exact error message** 
3. **Ask for help**: https://github.com/joshuafuller/atak-vns-offline-routing-generator/issues

## 🎉 You're Ready!

You now have:
- ✅ Docker installed and working
- ✅ VNS Generator downloaded and setup
- ✅ Your first routing data generated
- ✅ Knowledge of how to generate more regions

**Next steps:**
- Generate routing data for your area of operations
- Install on your ATAK devices
- Test offline routing in VNS

---

**🔄 Need to update later?** See our [Updating Guide](updating.md)