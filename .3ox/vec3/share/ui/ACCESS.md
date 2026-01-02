///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂///
▛//▞▞ ⟦⎊⟧ :: ⧗-25.145 // ACCESS.CONSOLE :: Network Instructions ▞▞

# 3OX Console :: Network Access Guide

## ▛▞ Server Status

✓ Server Running: WEBrick on port 8080
✓ Network Binding: 0.0.0.0 (accessible from any device)
✓ Console Path: /root/!CMD.BRIDGE/.3ox/vec3/share/ui/console.html

## ▛▞ Access URLs

### From This Machine (PC)
http://localhost:8080
http://127.0.0.1:8080

### From Your Phone/Telegram (Same Network)
http://172.20.210.72:8080

### From WSL2 (If running in WSL)
http://localhost:8080

## ▛▞ Quick Start

1. **Start Server** (if not running):
   ```bash
   cd /root/!CMD.BRIDGE/.3ox/vec3/bin
   ruby serve.console.rb
   ```

2. **Or use the quick launcher**:
   ```bash
   /root/!CMD.BRIDGE/.3ox/vec3/bin/start.console.sh
   ```

3. **Stop Server**:
   ```bash
   pkill -f 'ruby serve.console'
   ```

## ▛▞ Telegram Sharing

1. Open browser on your PC: http://localhost:8080
2. Share screen to Telegram
3. OR: Open in mobile browser: http://172.20.210.72:8080
4. Screenshot and send to Telegram

## ▛▞ Console Features

- **Run Quick Test** button - instantly test the system
- **Pheno Chain** input - structured operations (ρ{}.φ{}.τ{})
- **File Watcher** - live updates from .3ox/vec3/var/
- **Receipt Display** - automatic receipt fetching
- **Mobile Friendly** - responsive design for phones

## ▛▞ Troubleshooting

**Can't connect from phone?**
- Make sure phone is on same WiFi network
- Check if firewall is blocking port 8080
- Try: curl http://172.20.210.72:8080 (from PC)

**Server not starting?**
- Check if port 8080 is in use: `lsof -i :8080`
- Kill existing process: `pkill -f 'ruby serve.console'`
- Check Ruby is installed: `ruby --version`

**Console shows errors?**
- REST API must be running on port 7777
- Check: `curl http://localhost:7777/health`
- Console can still display but job submission needs API

## ▛▞ Network Architecture

```
┌─────────────────────────────────────┐
│  Your Phone/Telegram                │
│  http://172.20.210.72:8080          │
└──────────────┬──────────────────────┘
               │ WiFi/Network
               ▼
┌─────────────────────────────────────┐
│  WEBrick Server (Port 8080)         │
│  Serves: console.html               │
└──────────────┬──────────────────────┘
               │ Localhost
               ▼
┌─────────────────────────────────────┐
│  REST API (Port 7777)               │
│  Job submission & status            │
└──────────────┬──────────────────────┘
               │ Filesystem
               ▼
┌─────────────────────────────────────┐
│  .3ox/vec3/var/                     │
│  - queue/    (job files)            │
│  - receipts/ (results)              │
└─────────────────────────────────────┘
```

:: ∎

///▙▖▙▖▞▞▙▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂〘・.°𝚫〙
