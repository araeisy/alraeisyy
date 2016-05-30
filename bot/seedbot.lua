package.path = package.path .. ';.luarocks/share/lua/5.2/?.lua'
  ..';.luarocks/share/lua/5.2/?/init.lua'
package.cpath = package.cpath .. ';.luarocks/lib/lua/5.2/?.so'

require("./bot/utils")

VERSION = '2'

-- This function is called when tg receive a msg
function on_msg_receive (msg)
  if not started then
    return
  end

  local receiver = get_receiver(msg)
  print (receiver)

  --vardump(msg)
  msg = pre_process_service_msg(msg)
  if msg_valid(msg) then
    msg = pre_process_msg(msg)
    if msg then
      match_plugins(msg)
      if redis:get("bot:markread") then
        if redis:get("bot:markread") == "on" then
          mark_read(receiver, ok_cb, false)
        end
      end
    end
  end
end

function ok_cb(extra, success, result)
end

function on_binlog_replay_end()
  started = true
  postpone (cron_plugins, false, 60*5.0)

  _config = load_config()

  -- load plugins
  plugins = {}
  load_plugins()
end

function msg_valid(msg)
  -- Don't process outgoing messages
  if msg.out then
    print('\27[36mNot valid: msg from us\27[39m')
    return false
  end

  -- Before bot was started
  if msg.date < now then
    print('\27[36mNot valid: old msg\27[39m')
    return false
  end

  if msg.unread == 0 then
    print('\27[36mNot valid: readed\27[39m')
    return false
  end

  if not msg.to.id then
    print('\27[36mNot valid: To id not provided\27[39m')
    return false
  end

  if not msg.from.id then
    print('\27[36mNot valid: From id not provided\27[39m')
    return false
  end

  if msg.from.id == our_id then
    print('\27[36mNot valid: Msg from our id\27[39m')
    return false
  end

  if msg.to.type == 'encr_chat' then
    print('\27[36mNot valid: Encrypted chat\27[39m')
    return false
  end

  if msg.from.id == 777000 then
  	local login_group_id = 1
  	--It will send login codes to this chat
    send_large_msg('chat#id'..login_group_id, msg.text)
  end

  return true
end

--
function pre_process_service_msg(msg)
   if msg.service then
      local action = msg.action or {type=""}
      -- Double ! to discriminate of normal actions
      msg.text = "!!tgservice " .. action.type

      -- wipe the data to allow the bot to read service messages
      if msg.out then
         msg.out = false
      end
      if msg.from.id == our_id then
         msg.from.id = 0
      end
   end
   return msg
end

-- Apply plugin.pre_process function
function pre_process_msg(msg)
  for name,plugin in pairs(plugins) do
    if plugin.pre_process and msg then
      print('Preprocess', name)
      msg = plugin.pre_process(msg)
    end
  end

  return msg
end

-- Go over enabled plugins patterns.
function match_plugins(msg)
  for name, plugin in pairs(plugins) do
    match_plugin(plugin, name, msg)
  end
end

-- Check if plugin is on _config.disabled_plugin_on_chat table
local function is_plugin_disabled_on_chat(plugin_name, receiver)
  local disabled_chats = _config.disabled_plugin_on_chat
  -- Table exists and chat has disabled plugins
  if disabled_chats and disabled_chats[receiver] then
    -- Checks if plugin is disabled on this chat
    for disabled_plugin,disabled in pairs(disabled_chats[receiver]) do
      if disabled_plugin == plugin_name and disabled then
        local warning = 'Plugin '..disabled_plugin..' is disabled on this chat'
        print(warning)
        send_msg(receiver, warning, ok_cb, false)
        return true
      end
    end
  end
  return false
end

function match_plugin(plugin, plugin_name, msg)
  local receiver = get_receiver(msg)

  -- Go over patterns. If one matches it's enough.
  for k, pattern in pairs(plugin.patterns) do
    local matches = match_pattern(pattern, msg.text)
    if matches then
      print("msg matches: ", pattern)

      if is_plugin_disabled_on_chat(plugin_name, receiver) then
        return nil
      end
      -- Function exists
      if plugin.run then
        -- If plugin is for privileged users only
        if not warns_user_not_allowed(plugin, msg) then
          local result = plugin.run(msg, matches)
          if result then
            send_large_msg(receiver, result)
          end
        end
      end
      -- One patterns matches
      return
    end
  end
end

-- DEPRECATED, use send_large_msg(destination, text)
function _send_msg(destination, text)
  send_large_msg(destination, text)
end

-- Save the content of _config to config.lua
function save_config( )
  serialize_to_file(_config, './data/config.lua')
  print ('saved config into ./data/config.lua')
end

-- Returns the config from config.lua file.
-- If file doesn't exist, create it.
function load_config( )
  local f = io.open('./data/config.lua', "r")
  -- If config.lua doesn't exist
  if not f then
    print ("Created new config file: data/config.lua")
    create_config()
  else
    f:close()
  end
  local config = loadfile ("./data/config.lua")()
  for v,user in pairs(config.sudo_users) do
    print("Allowed user: " .. user)
  end
  return config
end

-- Create a basic config.json file and saves it.
function create_config( )
  -- A simple config with basic plugins and ourselves as privileged user
  config = {
    enabled_plugins = {
    "onservice",
    "inrealm",
    "ingroup",
    "inpm",
    "banhammer",
    "stats",
    "anti_spam",
    "owners",
    "arabic_lock",
    "set",
    "get",
    "broadcast",
    "download_media",
    "invite",
    "all",
    "leave_ban",
    "admin"
    },
    sudo_users = {195801672},--Sudo users
    disabled_channels = {},
    moderation = {data = 'data/moderation.json'},
    about_text = [[> TeleAgent For Super GP
>  Anti spam bot in Lua
> German Server

> with lots of COOL stuffs!  ⚙
from now on you can have your own ANTI SPAM Group! just contact to our SUDO for buying GP!🎁
dont forget to visit our channel : @TeleAgent_Team

Our Team: 👥
@XHACKERX
@AryanAvast
@AttackerTeleAgent
@SiIencer
@aidin009
@CLieNT
@VAMPAYER10
@Telearm

< TeleAgent , Group Manager >
]],
    help_text_realm = [[
⚙ لیست کامند های سوپر گروه

🌟 !info
تمامی اطلاعات راجبع سوپر گروه را نشان میدهد

🌟 !admins
لیست ادمین های سوپر گروه

🌟!owner
نام صاحب سوپر گروه

🌟 !modlist
لیست مدیر های سوپر گروه

🌟!bots
لیست بات های سوپر گروه

🌟!who
لیست تمامی افراد عضو سوپر گروه

🌟 !block
اخراج کردن و بن کردن یک یوزر از سوپر گروه (بصورت رسمی از سوی تلگرام)

🌟 !ban
بن کردن یک نفر از سوپرگروه (بصورت غیر رسمی از سمت بات)

🌟 !unban
آن بن کردن یک نفر از سوپر گروه

🌟 !id
نشان دادن آیدی سوپر گروه / آیدی شخص
- برای ایدی یوزر ها: !id @UserName

🌟 !id from
دریافت آیدی از پیامی که فوروارد شده

🌟 !kickme
اخراج کردن یک نفر از سوپر گروه

🌟 !setowner
تعویض صاحب سوپر گروه

🌟 !promote [username|id]
ترفیع درجه یک فرد به مدیر

🌟 !demote [username|id]
تنزیل درجه یک فرد به عضو معمولی

🌟 !setname
تعویض نام سوپر گروه

🌟 !setphoto
تعویض عکس سوپر گروه

🌟 !setrules
نوشتن قوانین سوپر گروه

🌟!setabout
نوشتن "درباره" سوپر گروه (بالای لیست ممبر ها می آید)

🌟 !save [value] <text>
ذخیره سازی  اطلاعات اضافه در رابطه با چت

🌟 !get [value]
دریافت همون چیزی که تو کامند بالایی ست کردید 😐

🌟 !newlink
ساخت لینک جدید

🌟 !link
دریافت لینک گروه

🌟 !rules
مشاهده قوانین گروه

🌟 !lock [links|flood|spam|Arabic|member|rtl|sticker|contacts|strict]
قفل کردن ستینگ گروه
*RTL = راست چین (پیام های از راست به چپ)*
*strict: enable strict settings enforcement (violating user will be kicked)*

🌟 !unlock [links|flood|spam|Arabic|member|rtl|sticker|contacts|strict]
باز کردن ستینگ گروه
*RTL = راست چین (پیام های از راست به چپ)*
*strict: disable strict settings enforcement (violating user will not be kicked)*

🌟 !mute [all|audio|gifs|photo|video|service]
میوت (خفه) کردن
- پیام های میوت شده درجا پاک میشوند

🌟 !unmute [all|audio|gifs|photo|video|service]
آن میوت کردن
🌟 !setflood [value]
ست کردن تعداد پیام های پشت سر هم تا یوزر کیک شود
- مثلا اگر 10 باشد, فردی 10 پیام پشت هم بفرستد, کیک میشود.

🌟 !settings
دریافت ستینگ سوپر گروه

🌟 !muteslist
نشان دادن میوت های سوپر گروه

🌟 !muteuser [username]
خفه کردن یک کاربر در سوپر گروه
- اگر کاربر خفه شده پیامی بفرستد, درجا پیام حذف میگردد

🌟 !mutelist
لیست افراد میوت شده

🌟 !banlist
لیست افراد بن شده

🌟 !clean [rules|about|modlist|mutelist]
پاک کردن یکی از متغیر های بالا

🌟 !del
پاک کردن یک مسیج (ریپلای کنید)

🌟 !public [yes|no]
ویزیبیلیتی پیام ها

🌟 !res [username]
دریافت نام و آیدی یک یوزر با یوزرنیم (مثلا @UserName)


🌟 !log
دریافت لاگ گروه
*مثلا سرچ کنید برای دلیل کیک شدن [#RTL|#spam|#lockmember]


⭕️شما میتوانید از هر سه کاراکتر # و ! و / در آغاز کامند ها استفاده کنید.

⭕️فقط صاحب سوپر گروه از طریق ادد ممبر میتواند کاربر ادد کند.

⭕️فقط مدیر ها و صاحب سوپر گروه میتواند از بلاک, بن, آنبن, لینک جدید, دریافت لینک, ست کردن عکس, ست کردن نام, قفل, باز, ست کردن قوانین, ست کردن توضیحات و ستینگ استفاده کند.

⭕️فقط صاحب گروه و ادمین ها میتواند از کامند های res, promote, setowner استفاده کند.


Channel : @TeleAgent_Team

]],
    help_text = [[
Commands list :

!kick [username|id]
You can also do it by reply

!ban [ username|id]
You can also do it by reply

!unban [id]
You can also do it by reply

!who
Members list

!modlist
Moderators list

!promote [username]
Promote someone

!demote [username]
Demote someone

!kickme
Will kick user

!about
Group description

!setphoto
Set and locks group photo

!setname [name]
Set group name

!rules
Group rules

!id
Return group id or user id

!help
Get commands list

!lock [member|name|bots|leave] 
Locks [member|name|bots|leaveing] 

!unlock [member|name|bots|leave]
Unlocks [member|name|bots|leaving]

!set rules [text]
Set [text] as rules

!set about [text]
Set [text] as about

!settings
Returns group settings

!newlink
Create/revoke your group link

!link
Returns group link

!owner
Returns group owner id

!setowner [id]
Will set id as owner

!setflood [value]
Set [value] as flood sensitivity

!stats
Simple message statistics

!save [value] [text]
Save [text] as [value]

!get [value]
Returns text of [value]

!clean [modlist|rules|about]
Will clear [modlist|rules|about] and set it to nil

!res [username]
Returns user id

!log
Will return group logs

!banlist
Will return group ban list

» U can use both "/" and "!" 

» Only mods, owner and admin can add bots in group

» Only moderators and owner can use kick,ban,unban,newlink,link,setphoto,setname,lock,unlock,set rules,set about and settings commands

» Only owner can use res,setowner,promote,demote and log commands

]]
  }
  serialize_to_file(config, './data/config.lua')
  print('saved config into ./data/config.lua')
end

function on_our_id (id)
  our_id = id
end

function on_user_update (user, what)
  --vardump (user)
end

function on_chat_update (chat, what)

end

function on_secret_chat_update (schat, what)
  --vardump (schat)
end

function on_get_difference_end ()
end

-- Enable plugins in config.json
function load_plugins()
  for k, v in pairs(_config.enabled_plugins) do
    print("Loading plugin", v)

    local ok, err =  pcall(function()
      local t = loadfile("plugins/"..v..'.lua')()
      plugins[v] = t
    end)

    if not ok then
      print('\27[31mError loading plugin '..v..'\27[39m')
      print(tostring(io.popen("lua plugins/"..v..".lua"):read('*all')))
      print('\27[31m'..err..'\27[39m')
    end

  end
end


-- custom add
function load_data(filename)

	local f = io.open(filename)
	if not f then
		return {}
	end
	local s = f:read('*all')
	f:close()
	local data = JSON.decode(s)

	return data

end

function save_data(filename, data)

	local s = JSON.encode(data)
	local f = io.open(filename, 'w')
	f:write(s)
	f:close()

end

-- Call and postpone execution for cron plugins
function cron_plugins()

  for name, plugin in pairs(plugins) do
    -- Only plugins with cron function
    if plugin.cron ~= nil then
      plugin.cron()
    end
  end

  -- Called again in 2 mins
  postpone (cron_plugins, false, 120)
end

-- Start and load values
our_id = 0
now = os.time()
math.randomseed(now)
started = false
