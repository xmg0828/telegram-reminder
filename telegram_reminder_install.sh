#!/bin/bash

echo "开始安装 Telegram Reminder 交互式版本..."

# 更新系统并安装必要的依赖
echo "安装系统依赖..."
apt-get update
apt-get install -y nodejs npm

# 创建项目目录
echo "创建项目目录..."
mkdir -p /root/telegram_reminder_interactive
cd /root/telegram_reminder_interactive

# 初始化 Node.js 项目
echo "初始化 Node.js 项目..."
npm init -y

# 安装项目依赖
echo "安装项目依赖..."
npm install express body-parser node-telegram-bot-api moment moment-timezone

# 写入改进版 app.js
echo "创建应用程序文件..."
cat > app.js << 'INNER'
const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const TelegramBot = require('node-telegram-bot-api');
const moment = require('moment-timezone');

const app = express();
const PORT = 3005;

let reminders = [];
let config = { token: '', chatId: '' };
const configPath = './config.json';
const dataPath = './reminders.json';

// 设置时区为中国时间
moment.tz.setDefault('Asia/Shanghai');

if (fs.existsSync(configPath)) {
    config = JSON.parse(fs.readFileSync(configPath));
}
if (fs.existsSync(dataPath)) {
    reminders = JSON.parse(fs.readFileSync(dataPath));
}

let bot = config.token ? new TelegramBot(config.token, { polling: true }) : null;

app.use(bodyParser.urlencoded({ extended: false }));

function saveReminders() {
    fs.writeFileSync(dataPath, JSON.stringify(reminders, null, 2));
}

function saveConfig() {
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
}

function sendReminder(reminder) {
    if (bot && config.chatId) {
        const message = `⏰ *提醒事项*\n\n*标题：* ${reminder.title}\n*内容：* ${reminder.content}\n*时间：* ${moment(reminder.time).format('YYYY-MM-DD HH:mm')}`;
        bot.sendMessage(config.chatId, message, { parse_mode: 'Markdown' });
    }
}

// 获取下一次提醒的时间
function getNextReminderTime(reminder) {
    const reminderDate = moment(reminder.time);
    
    if (reminder.repeat === '每天') {
        return reminderDate.add(1, 'days').toDate();
    } else if (reminder.repeat === '每周') {
        return reminderDate.add(1, 'weeks').toDate();
    } else if (reminder.repeat === '每月') {
        const currentDay = reminderDate.date();
        const nextMonth = reminderDate.add(1, 'months');
        const lastDayOfNextMonth = nextMonth.endOf('month').date();
        
        if (currentDay > lastDayOfNextMonth) {
            nextMonth.date(lastDayOfNextMonth);
        } else {
            nextMonth.date(currentDay);
        }
        
        return nextMonth.toDate();
    }
    
    return null;
}

// Telegram Bot 命令处理
if (bot) {
    // /help 命令
    bot.onText(/\/help/, (msg) => {
        const chatId = msg.chat.id;
        const helpMessage = `
*Telegram提醒助手命令列表*

/help - 显示帮助信息
/all - 显示所有提醒
/add - 添加提醒（会引导你输入详细信息）
/del <序号> - 删除指定提醒
/daily - 添加每日提醒
/weekly - 添加每周提醒
/monthly - 添加每月提醒

*添加提醒格式：*
/add 标题,内容,时间
例如：/add 开会,参加产品会议,2024-12-20 14:00

*快速添加重复提醒：*
/daily 标题,内容,时间 - 添加每日提醒
/weekly 标题,内容,时间 - 添加每周提醒
/monthly 标题,内容,时间 - 添加每月提醒

时间格式：YYYY-MM-DD HH:mm
        `;
        bot.sendMessage(chatId, helpMessage, { parse_mode: 'Markdown' });
    });
    
    // /all 命令 - 显示所有提醒
    bot.onText(/\/all/, (msg) => {
        const chatId = msg.chat.id;
        if (reminders.length === 0) {
            bot.sendMessage(chatId, '当前没有任何提醒事项');
            return;
        }
        
        let message = '*所有提醒事项：*\n\n';
        reminders.forEach((r, index) => {
            const timeStr = moment(r.time).format('YYYY-MM-DD HH:mm');
            const repeatText = r.repeat ? `[${r.repeat}]` : '[仅一次]';
            const status = r.sent ? '✅已发送' : '❌待发送';
            message += `${index + 1}. *${r.title}*\n   内容：${r.content}\n   时间：${timeStr}\n   类型：${repeatText}\n   状态：${status}\n\n`;
        });
        
        bot.sendMessage(chatId, message, { parse_mode: 'Markdown' });
    });
    
    // /add 命令 - 添加提醒
    bot.onText(/\/add(.*)/, (msg, match) => {
        const chatId = msg.chat.id;
        const input = match[1].trim();
        
        if (!input) {
            bot.sendMessage(chatId, '请使用格式：/add 标题,内容,时间\n例如：/add 开会,参加产品会议,2024-12-20 14:00');
            return;
        }
        
        const parts = input.split(',').map(s => s.trim());
        if (parts.length !== 3) {
            bot.sendMessage(chatId, '格式错误！请使用：/add 标题,内容,时间');
            return;
        }
        
        const [title, content, timeStr] = parts;
        const time = moment(timeStr, 'YYYY-MM-DD HH:mm');
        
        if (!time.isValid()) {
            bot.sendMessage(chatId, '时间格式错误！请使用 YYYY-MM-DD HH:mm 格式');
            return;
        }
        
        reminders.push({
            title,
            content,
            time: time.toISOString(),
            sent: false,
            repeat: null,
            createdAt: new Date().toISOString()
        });
        
        saveReminders();
        bot.sendMessage(chatId, `✅ 提醒已添加：\n标题：${title}\n内容：${content}\n时间：${timeStr}`);
    });
    
    // /del 命令 - 删除提醒
    bot.onText(/\/del (.+)/, (msg, match) => {
        const chatId = msg.chat.id;
        const index = parseInt(match[1]) - 1;
        
        if (isNaN(index) || index < 0 || index >= reminders.length) {
            bot.sendMessage(chatId, '无效的序号！请使用 /all 查看所有提醒的序号');
            return;
        }
        
        const deleted = reminders[index];
        reminders.splice(index, 1);
        saveReminders();
        
        bot.sendMessage(chatId, `✅ 已删除提醒：${deleted.title}`);
    });
    
    // /daily, /weekly, /monthly 命令 - 添加重复提醒
    ['daily', 'weekly', 'monthly'].forEach(repeatType => {
        const repeatMap = {
            daily: '每天',
            weekly: '每周',
            monthly: '每月'
        };
        
        bot.onText(new RegExp(`\\/${repeatType}(.*)`), (msg, match) => {
            const chatId = msg.chat.id;
            const input = match[1].trim();
            
            if (!input) {
                bot.sendMessage(chatId, `请使用格式：/${repeatType} 标题,内容,时间\n例如：/${repeatType} 晨会,参加每日晨会,09:00`);
                return;
            }
            
            const parts = input.split(',').map(s => s.trim());
            if (parts.length !== 3) {
                bot.sendMessage(chatId, '格式错误！请使用：标题,内容,时间');
                return;
            }
            
            const [title, content, timeStr] = parts;
            let time;
            
            // 处理简短时间格式（如 09:00）
            if (timeStr.match(/^\d{1,2}:\d{2}$/)) {
                time = moment(timeStr, 'HH:mm');
                // 如果时间已过，设置为明天的这个时间
                if (time.isBefore(moment())) {
                    time.add(1, 'days');
                }
            } else {
                time = moment(timeStr, 'YYYY-MM-DD HH:mm');
            }
            
            if (!time.isValid()) {
                bot.sendMessage(chatId, '时间格式错误！请使用 HH:mm 或 YYYY-MM-DD HH:mm 格式');
                return;
            }
            
            reminders.push({
                title,
                content,
                time: time.toISOString(),
                sent: false,
                repeat: repeatMap[repeatType],
                createdAt: new Date().toISOString()
            });
            
            saveReminders();
            bot.sendMessage(chatId, `✅ ${repeatMap[repeatType]}提醒已添加：\n标题：${title}\n内容：${content}\n首次提醒时间：${time.format('YYYY-MM-DD HH:mm')}`);
        });
    });
    
    // 设置聊天ID（首次使用时自动设置）
    bot.on('message', (msg) => {
        if (!config.chatId) {
            config.chatId = msg.chat.id.toString();
            saveConfig();
            console.log(`自动设置 Chat ID: ${config.chatId}`);
        }
    });
}

// Web路由保持不变...
app.get('/', (req, res) => {
    const now = new Date();
    let listItems = reminders.map((r, index) => {
        const timeStr = moment(r.time).format('YYYY-MM-DD HH:mm');
        const repeatText = r.repeat ? `[${r.repeat}提醒]` : '[仅一次提醒]';
        // 添加不同的样式来区分即将到期的提醒
        let style = '';
        const reminderDate = new Date(r.time);
        const diffTime = reminderDate - now;
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
        
        if (diffDays <= 0) {
            style = 'color:red;font-weight:bold;';
        } else if (diffDays <= 3) {
            style = 'color:orange;';
        }
        
        return `<li style="font-size:18px;margin-bottom:10px;${style}">${r.title} - ${timeStr} ${repeatText} - ${r.sent ? '✅已发送' : '❌待发送'} <a href="/delete/${index}" style="color:red;margin-left:10px;">❌删除</a></li>`;
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
        .info { background:#e3f2fd; padding:15px; border-radius:8px; margin:20px 0; text-align:left; }
      </style>
    </head>
    <body>
      <div class="container">
        <h2>Telegram提醒系统</h2>
        
        <div class="info">
          <strong>Bot已激活!</strong> 在Telegram中发送 /help 查看命令列表<br>
          Chat ID: ${config.chatId || '未设置'}
        </div>
        
        <h3>Web添加提醒</h3>
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
        .warning { background:#fff3cd; color:#856404; padding:15px; border-radius:8px; margin:20px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <h2>设置 Telegram 配置</h2>
        <form action="/saveConfig" method="post">
          <input type="text" name="token" value="${config.token}" placeholder="Bot Token" required><br>
          <input type="text" name="chatId" value="${config.chatId}" placeholder="Chat ID（可选，会自动获取）"><br>
          <button type="submit">保存配置</button>
        </form>
        
        <div class="warning">
          <strong>注意：</strong>更改Bot Token后需要重启服务！<br>
          Chat ID会在首次发送消息时自动设置。
        </div>
        
        <br>
        <a href="/">返回主页</a>
      </div>
    </body>
    </html>
    `);
});

app.post('/saveConfig', (req, res) => {
    const oldToken = config.token;
    config.token = req.body.token;
    config.chatId = req.body.chatId;
    saveConfig();
    
    // 如果token改变，需要重新创建bot
    if (oldToken !== config.token) {
        if (bot) {
            bot.stopPolling();
        }
        bot = new TelegramBot(config.token, { polling: true });
    }
    
    res.redirect('/');
});

app.post('/add', (req, res) => {
    const { title, content, time, repeat } = req.body;
    reminders.push({ 
        title, 
        content, 
        time: new Date(time).toISOString(), 
        sent: false, 
        repeat,
        createdAt: new Date().toISOString()
    });
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

// 提醒检查和处理函数
function checkAndProcessReminders() {
    const now = new Date();
    let hasChanges = false;
    
    reminders.forEach((reminder, index) => {
        const reminderTime = new Date(reminder.time);
        
        // 检查是否到了提醒时间
        if (!reminder.sent && reminderTime <= now) {
            // 发送提醒
            sendReminder(reminder);
            reminder.sent = true;
            hasChanges = true;
            
            // 如果是重复提醒，则创建下一次提醒
            if (reminder.repeat) {
                const nextTime = getNextReminderTime(reminder);
                if (nextTime) {
                    reminder.time = nextTime.toISOString();
                    reminder.sent = false;
                }
            }
        }
    });
    
    // 如果有变更，保存提醒列表
    if (hasChanges) {
        saveReminders();
    }
}

// 每30秒检查一次提醒
setInterval(checkAndProcessReminders, 30000);

// 程序启动时立即检查一次
checkAndProcessReminders();

app.listen(PORT, () => {
    console.log(`✅ 提醒服务已启动，访问 http://你的IP:${PORT}`);
    if (config.token) {
        console.log('✅ Telegram Bot 已激活，发送 /help 查看命令');
    } else {
        console.log('⚠️  请先配置 Telegram Bot Token');
    }
});
INNER

# 创建 systemd 服务文件
echo "创建 systemd 服务..."
cat > /etc/systemd/system/reminder_interactive.service << 'SERVICE'
[Unit]
Description=Telegram Reminder Interactive Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/telegram_reminder_interactive
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
systemctl enable reminder_interactive
systemctl start reminder_interactive

# 检查服务状态
echo "检查服务状态..."
systemctl status reminder_interactive

echo ""
echo "✅ Telegram Reminder 交互式版本安装完成！"
echo ""
echo "使用说明："
echo "1. Web界面: http://你的IP:3005"
echo "2. 首次访问需要配置 Telegram Bot Token"
echo "3. 配置完成后，在Telegram中向你的Bot发送 /help 查看所有命令"
echo ""
echo "Telegram 命令列表："
echo "/help    - 显示帮助信息"
echo "/all     - 显示所有提醒"
echo "/add     - 添加提醒"
echo "/del     - 删除提醒"
echo "/daily   - 添加每日提醒"
echo "/weekly  - 添加每周提醒"
echo "/monthly - 添加每月提醒"
echo ""
