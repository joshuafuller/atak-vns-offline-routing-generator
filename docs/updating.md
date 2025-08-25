# 🔄 Updating to Latest Version

Get the latest bug fixes, new regions, and improvements.

## 🚀 Easy Update (Most People)

**If you downloaded this as a ZIP file:**
1. Go to https://github.com/joshuafuller/atak-vns-offline-routing-generator
2. Click the green **"Code"** button
3. Click **"Download ZIP"**
4. Extract the new ZIP file
5. Copy your old `output/` and `cache/` folders to the new folder
6. Delete the old folder, keep the new one

Your generated routing files are safe - they're in the `output/` folder.

## ⚡ Advanced Update (If You Know Git)

**If you used `git clone` to download:**
```bash
git pull
```

## 🐳 Docker Update (Automatic)

**Good news:** Docker images update automatically when you run `./run.sh`

**If something seems wrong, try this:**
1. Open your terminal/command prompt
2. Type: `./run.sh [your-region]` (replace [your-region] with your actual region)
3. It will download the newest version automatically

## ✨ What Gets Updated

- ✅ **Bug fixes** - Problems get fixed automatically
- ✅ **New regions** - More countries and states become available  
- ✅ **Faster processing** - Performance improvements
- ✅ **Better maps** - Updated map data from OpenStreetMap

## 🛡️ Your Files Are Safe

**Don't worry!** Updates never delete your work:

- ✅ Your generated routing files (in `output/` folder) are safe
- ✅ Your downloaded map data (in `cache/` folder) is safe
- ✅ Your ZIP files are safe

## 🔍 See What Regions Are Available

After updating, check for new regions:
```bash
./list-regions.sh
```
This shows all available countries and states you can generate.

## 🆘 Having Problems?

**Step 1:** Try running your region again
```bash
./run.sh [your-region-name]
```

**Step 2:** If that doesn't work, download a fresh copy from GitHub (see "Easy Update" above)

**Step 3:** Still stuck? [Ask for help on GitHub](https://github.com/joshuafuller/atak-vns-offline-routing-generator/issues) - we're friendly!