#!/bin/bash

echo "开始安装 Telegram Reminder 美化版..."

# 更新系统并安装必要的依赖
echo "安装系统依赖..."
apt-get update
apt-get install -y nodejs npm

# 创建项目目录
echo "创建项目目录..."
mkdir -p /root/telegram_reminder_local
cd /root/telegram_reminder_local

# 初始化 Node.js 项目
echo "初始化 Node.js 项目..."
npm init -y

# 安装项目依赖
echo "安装项目依赖..."
npm install express body-parser node-telegram-bot-api

# 写入美化版 app.js
echo "创建应用程序文件..."
cat > app.js << 'INNER'
const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const TelegramBot = require('node-telegram-bot-api');

const app = express();
const PORT = 3005;

let reminders = [];
let config = { token: '', chatId: '' };
const configPath = './config.json';
const dataPath = './reminders.json';

if (fs.existsSync(configPath)) {
    config = JSON.parse(fs.readFileSync(configPath));
}
if (fs.existsSync(dataPath)) {
    reminders = JSON.parse(fs.readFileSync(dataPath));
}

let bot = config.token ? new TelegramBot(config.token, { polling: false }) : null;

app.use(bodyParser.urlencoded({ extended: false }));

function saveReminders() {
    fs.writeFileSync(dataPath, JSON.stringify(reminders, null, 2));
}

function saveConfig() {
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

function sendReminder(reminder) {
    if (bot && config.chatId) {
        const message = `⏰ *提醒事项*\n\n*标题：* ${reminder.title}\n*内容：* ${reminder.content}\n*时间：* ${new Date(reminder.time).toLocaleString('zh-CN')}`;
        bot.sendMessage(config.chatId, message, { parse_mode: 'Markdown' });
    }
}

app.get('/', (req, res) => {
    const now = new Date();
    let listItems = reminders.map((r, index) => {
        const timeStr = new Date(r.time).toLocaleString('zh-CN');
        const repeatText = r.repeat ? `[${r.repeat}提醒]` : '[仅一次提醒]';
        return `<li style="font-size:18px;margin-bottom:10px;">${r.title} - ${timeStr} ${repeatText} - ${r.sent ? '✅已发送' : '❌待发送'} <a href="/delete/${index}" style="color:red;margin-left:10px;">❌删除</a></li>`;
    }).join('');

    res.send(`
    <html>
    <head>
      <meta charset="UTF-8">
      <title>Telegram提醒系统</title>
      <style>
        body { background:#f5f5f5; font-family:Roboto,sans-serif; text-align:center; }
        .container { margin:50px auto; max-width:600px; background:white; padding:30px; border-radius:15px; box-shadow:0 2px 10px rgba(0,0,0,0.1);}
        input, select, button { width:100%; padding:10px; margin:10px 0; font-size:16px; border-radius:8px; border:1px solid #ccc; }
        button { background:#4CAF50; color:white; border:none; cursor:pointer; }
        button:hover { background:#45a049; }
        ul { text-align:left; margin-top:20px; padding-left:0; list-style:none; }
      </style>
    </head>
    <body>
      <div class="container">
        <h2>添加提醒事项</h2>
        <form action="/add" method="post">
          <input type="text" name="title" placeholder="标题" required><br>
          <input type="text" name="content" placeholder="内容" required><br>
          <input type="datetime-local" name="time" required><br>
          <select name="repeat">
            <option value="">仅一次</option>
            <option value="每天">每天</option>
            <option value="每周">每周</option>
            <option value="每月">每月</option>
          </select><br>
          <button type="submit">提交提醒</button>
        </form>

        <h3>提醒列表：</h3>
        <ul>${listItems}</ul>

        <br>
        <a href="/config">配置 Telegram</a>
      </div>
    </body>
    </html>
    `);
});

app.get('/config', (req, res) => {
    res.send(`
    <html>
    <head>
      <meta charset="UTF-8">
      <title>配置 Telegram</title>
      <style>
        body { background:#f5f5f5; font-family:Roboto,sans-serif; text-align:center; }
        .container { margin:50px auto; max-width:600px; background:white; padding:30px; border-radius:15px; box-shadow:0 2px 10px rgba(0,0,0,0.1);}
        input, button { width:100%; padding:10px; margin:10px 0; font-size:16px; border-radius:8px; border:1px solid #ccc; }
        button { background:#4CAF50; color:white; border:none; cursor:pointer; }
        button:hover { background:#45a049; }
      </style>
    </head>
    <body>
      <div class="container">
        <h2>设置 Telegram 配置</h2>
        <form action="/saveConfig" method="post">
          <input type="text" name="token" value="${config.token}" placeholder="Bot Token" required><br>
          <input type="text" name="chatId" value="${config.chatId}" placeholder="Chat ID" required><br>
          <button type="submit">保存配置</button>
        </form>
        <br>
        <a href="/">返回主页</a>
      </div>
    </body>
    </html>
    `);
});

app.post('/saveConfig', (req, res) => {
    config.token = req.body.token;
    config.chatId = req.body.chatId;
    saveConfig();
    bot = new TelegramBot(config.token, { polling: false });
    res.redirect('/');
});

app.post('/add', (req, res) => {
    const { title, content, time, repeat } = req.body;
    reminders.push({ title, content, time: new Date(time).toISOString(), sent: false, repeat });
    saveReminders();
    res.redirect('/');
});

app.get('/delete/:index', (req, res) => {
    const index = req.params.index;
    if (reminders[index]) {
        reminders.splice(index, 1);
        saveReminders();
    }
    res.redirect('/');
});

setInterval(() => {
    const now = new Date();
    reminders.forEach((reminder, index) => {
        if (!reminder.sent && new Date(reminder.time) <= now) {
            sendReminder(reminder);
            reminder.sent = true;
            if (reminder.repeat === '每天') {
                reminder.time = new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString();
                reminder.sent = false;
            } else if (reminder.repeat === '每周') {
                reminder.time = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString();
                reminder.sent = false;
            } else if (reminder.repeat === '每月') {
                const date = new Date(reminder.time);
                date.setMonth(date.getMonth() + 1);
                reminder.time = date.toISOString();
                reminder.sent = false;
            }
            saveReminders();
        }
    });
}, 30000);

app.listen(PORT, () => {
    console.log(`✅ 提醒服务已启动，访问 http://你的IP:${PORT}`);
});
INNER

# 创建 systemd 服务文件
echo "创建 systemd 服务..."
cat > /etc/systemd/system/reminder_local.service << 'SERVICE'
[Unit]
Description=Telegram Reminder Local Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/telegram_reminder_local
ExecStart=/usr/bin/node app.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

# 重新加载 systemd 配置
echo "重新加载 systemd 配置..."
systemctl daemon-reload

# 启用并启动服务
echo "启动服务..."
systemctl enable reminder_local
systemctl start reminder_local

# 检查服务状态
echo "检查服务状态..."
systemctl status reminder_local

echo ""
echo "✅ Telegram Reminder 美化版安装完成！"
echo "访问地址: http://你的IP:3005"
echo "首次访问需要配置 Telegram Bot Token 和 Chat ID"
echo ""
