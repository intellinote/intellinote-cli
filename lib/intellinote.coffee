readline = require 'readline'
fs       = require 'fs'
path     = require 'path'
request  = require 'request'

TILDE = process.env.HOME || process.env.HOMEPATH || process.env.USERPROFILE
CONFIG_FILE = path.join(TILDE,'.intellinote')
REFRESH_ACCESS_TOKEN_AFTER = 15*60*1000

make_readline = ( args... )=>
  rl = readline.createInterface args...
  rl.dehistory = (cnt=1)=>
    for i in [1..cnt]
      rl.history = rl.history.slice(1)

  rl.hidden = (query, callback)=>
    stdin = process.openStdin()
    listener = (char)->
      char = char + "";
      switch char
        when "\n","\r","\u0004"
          stdin.removeListener("data",listener)
        else
          process.stdout.write "\x1b[2K\x1b[200D" + query + Array(rl.line.length+1).join("*")
    process.stdin.on "data", listener
    rl.question query, (value)->
      rl.history = rl.history.slice(1)
      callback(value)
  rl.multiline = (query, callback)=>
    listeners = []
    remove_listeners = ()=>
      for [obj,event,listener] in listeners
        obj?.removeListener event, listener
    add_listener = (obj,event,listener)=> obj.on event, listener
    lines = []
    last_was_ctrl_x = false
    readline.emitKeypressEvents(process.stdin)
    keypress_listener = (key,event)=>
      if event?.sequence is '\u0018'
        last_was_ctrl_x = true
      else if event?.sequence is '\u0005'
        if last_was_ctrl_x
          fs.writeFileSync("test.txt",lines.join("\n"))
          remove_listeners()
          rl.pause()
          editor = require('editor')
          editor 'test.txt', (code,sig)=>
            console.log code, sig
            lines = fs.readFileSync("test.txt").toString()
            callback(lines)
            return
        else
          last_was_ctrl_x = false
      else
        last_was_ctrl_x = false
    add_listener process.stdin, 'keypress', keypress_listener
    old_prompt = rl._prompt
    rl.setPrompt "#{query} (Ctrl+D to stop or Ctrl+X Ctrl+E to edit)\n#{old_prompt}"
    rl.prompt()
    rl.setPrompt(old_prompt)
    line_listener = (line)=>
      lines.push line
      rl.dehistory()
      rl.prompt()
    close_listener = ()=>
      remove_listeners()
      callback(lines.join("\n"),lines)
    add_listener rl, 'line', line_listener
    add_listener rl, 'close', close_listener
  return rl

class Intellinote

  config: null

  set_default_config:()=>
    @config ?= {}
    @config.v ?= "1"
    @config.server ?= {}
    @config.server.host ?= "api.intellinote.net"
    @config.server.port ?= 443
    @config.server.base ?= "/rest"
    @config.oauth ?= {}
    @config.oauth.client_id ?= "incli-H19qHfQb"
    @config.oauth.scope ?= "read,write"
    @config.oauth.redirect_uri ?= "/"

  abs:(path)=>
    if /^https\/\/\//.test path
      return path
    else
      url = "https://#{@config.server.host}"
      unless @config.server.port is 443
        url += ":#{@config.server.port}"
      url += @config.server.base ? ""
      url += path
      return url

  read_config:(callback)=>
    if fs.existsSync(CONFIG_FILE)
      try
        @config = JSON.parse(fs.readFileSync(CONFIG_FILE))
      catch err
        @config = {}
    @set_default_config()
    callback(null)

  write_config:(callback)=>
    fs.writeFileSync(CONFIG_FILE,JSON.stringify(@config,null,2)+"\n")
    callback(null)

  get_credentials: (callback)=>
    rl = readline.createInterface { input: process.stdin, output: process.stdout }
    rl.hidden = (query, callback)=>
      stdin = process.openStdin()
      listener = (char)->
        char = char + "";
        switch char
          when "\n","\r","\u0004"
            stdin.removeListener("data",listener)
          else
            process.stdout.write "\x1b[2K\x1b[200D" + query + Array(rl.line.length+1).join("*")
      process.stdin.on "data", listener
      rl.question query, (value)->
        rl.history = rl.history.slice(1)
        callback(value)
    rl.question "Username? ", (uname)=>
      rl.hidden "Password? ", (passwd)=>
        rl.close()
        callback(null,uname,passwd)

  get_refresh_token:(username,password,callback)=>
    cookie_jar = request.jar()
    params = {
      url:@abs "/log-in"
      body:{ username:username, password:password }
      jar:cookie_jar
      json:true
    }
    request.post params, (err,response,body)=>
      unless response?.statusCode is 302
        callback(new Error("Failed to authenticate."))
      else
        params = {
          url:@abs "/auth/oauth2/authorization/granted?response_type=code&client_id=#{@config.oauth.client_id}&scope=#{@config.oauth.scope}&redirect_uri=#{@config.oauth.redirect_uri}"
          jar:cookie_jar
          followRedirect:false
        }
        request.get params, (err,response,body)=>
          unless response?.statusCode is 302 and response?.headers?.location?
            callback(new Error("Failed to authorize."))
          else
            @config ?= {}
            @config.oauth ?= {}
            @config.oauth.refresh = response.headers.location.match(/^\/\?code=([^&$]+)(&|$)/)?[1]
            callback(null)


  get_access_token:(callback)=>
    params = {
      url:@abs "/auth/oauth2/access"
      body:{
        code:@config.oauth.refresh
        client_id:@config.oauth.client_id
        client_secret:@config.oauth.client_secret ? "G0wUG00TJ1FXNR"
        grant_type:"authorization_code"
      }
      jar:null
      json:true
    }
    request.post params, (err,response,body)=>
      unless response?.statusCode is 200 and body?.access_token?
        callback(new Error("Failed to get access token."))
      else
        @config ?= {}
        @config.oauth ?= {}
        @config.oauth.access = body.access_token
        if body.refresh_token?
          @config.oauth.refresh = body.refresh_token
        @config.oauth.refreshed = Date.now()
        callback(null)

  # get_orgs:(callback)=>
  #   params = {
  #     url:@abs("/v2.0/orgs")
  #     headers: {
  #       Authorization: "Bearer #{@config.oauth.access}"
  #     }
  #     jar:null
  #     json:true
  #   }
  #   request.get params, (err,response,body)=>
  #     callback err,response?.statusCode,body

  ping:(callback)=>
    params = {
      url:@abs "/v2.0/ping/authed"
      headers: {
        Authorization: "Bearer #{@config.oauth.access}"
      }
      jar:null
      json:true
    }
    request.get params, (err,response,body)=>
      callback err,response?.statusCode,body

  ensure_access_token:(callback)=>
    if @config.oauth?.access? and @config.oauth?.refreshed? and (Date.now() - @config.oauth.refreshed) < REFRESH_ACCESS_TOKEN_AFTER
      callback(null,true)
    else
      delete @config.oauth?.access
      delete @config.oauth?.refreshed
      @ensure_active_access_token(callback)

  ensure_active_access_token:(callback)=>
    if @config.oauth?.access?
      @ping (err,status_code,body)=>
        unless status_code is 200 and body?.timestamp?
          delete @config.oauth.access
          @ensure_active_access_token(callback)
        else
          callback(null,true)
    else if @config.oauth?.refresh?
      @get_access_token (err)=>
        @ping (err,status_code,body)=>
          unless status_code is 200 and body?.timestamp?
            delete @config.oauth.refresh
            @ensure_active_access_token(callback)
          else
            @write_config ()=>
              callback(null,true)
    else
      @get_credentials (err,u,p)=>
        @get_refresh_token u,p,(err)=>
          @get_access_token (err)=>
            @ping (err,status_code,body)=>
              unless status_code is 200 and body?.timestamp?
                callback(new Error("Unable to obtain an access token"),false)
              else
                @write_config ()=>
                  callback(null,true)

  list_orgs:(callback)=>
    params = {
      url:@abs("/v2.0/orgs")
      headers: { Authorization: "Bearer #{@config.oauth.access}" }
      jar:null
      json:true
    }
    request.get params, (err,response,body)=>
      if err?
        callback(err)
      else unless /^2[0-9][0-9]$/.test "#{response?.statusCode}"
        callback(new Error("Non-2xx-series status code (#{response?.statusCode})"))
      else
        callback null,body

  list_workspaces:(org_id,callback)=>
    params = {
      url:@abs("/v2.0/org/#{org_id}/workspaces")
      headers: { Authorization: "Bearer #{@config.oauth.access}" }
      jar:null
      json:true
    }
    request.get params, (err,response,body)=>
      if err?
        callback(err)
      else unless /^2[0-9][0-9]$/.test "#{response?.statusCode}"
        callback(new Error("Non-2xx-series status code (#{response?.statusCode})"))
      else
        callback null,body

  list_notes:(org_id,workspace_id,note_type,callback)=>
    params = {
      url:@abs("/v2.0/org/#{org_id}/workspace/#{workspace_id}/notes?note_type=#{note_type}")
      headers: { Authorization: "Bearer #{@config.oauth.access}" }
      jar:null
      json:true
    }
    request.get params, (err,response,body)=>
      if err?
        callback(err)
      else unless /^2[0-9][0-9]$/.test "#{response?.statusCode}"
        callback(new Error("Non-2xx-series status code (#{response?.statusCode})"))
      else
        callback null,body

  _menu:(prompt,choices,dflt_key,callback)=>
    unless choices?.length > 0
      callback(null,null)
    else
      dflt_index = 1
      console.log prompt
      for choice,i in choices
        key= choice[0]
        label = choice[1]
        console.log "  [#{i+1}] #{label}"
        if key is dflt_key
          dflt_index = i+1
      rl = make_readline { input: process.stdin, output: process.stdout }
      rl.question "[#{dflt_index}]> ", (selection)=>
        if /^\s*$/.test selection
          selection = dflt_index
        else if /^\s*[0-9]\s*$/.test selection
          selection = parseInt(selection)
        rl.close()
        unless 1 <= selection <= choices.length
          console.log "\nNot Valid\n"
          @_menu(prompt,choices,dflt_key,callback)
        else
          callback(null,choices[selection-1][0])

  choose_org:(callback)=>
    @list_orgs (err,orgs)=>
      if err?
        callback(err)
      else
        options = []
        for org,i in orgs
          options.push [org.org_id,"#{org.name} (#{org.org_id})"]
        dflt = @config?.current?.org_id
        @_menu "Choose Org",options,dflt,(err,org_id)=>
          if err?
            callback(err)
          else
            callback(null,org_id)

  choose_workspace:(org_id,callback)=>
    @list_workspaces org_id,(err,workspaces)=>
      if err?
        callback(err)
      else
        options = []
        for workspace,i in workspaces
          options.push [workspace.workspace_id,"#{workspace.name} (#{workspace.workspace_id})"]
        dflt = @config?.current?.workspace_id
        @_menu "Choose Workpace",options,dflt,(err,workspace_id)=>
          if err?
            callback(err)
          else
            callback(null,workspace_id)

  choose_note:(org_id,workspace_id,note_type,callback)=>
    @list_notes org_id,workspace_id,note_type,(err,notes)=>
      if err?
        callback(err)
      else
        options = []
        for note,i in notes
          options.push [note.note_id,"#{note.title} (#{note.note_id})"]
        dflt = @config?.current?.note_id
        if note_type is 'task'
          prompt = 'Task'
        else
          prompt = 'Note'
        @_menu "Choose #{prompt}",options,dflt,(err,note_id)=>
          if err?
            callback(err)
          else
            callback(null,note_id)

  _request:(method,uri,body,stream,callback)=>
    params = {
      url:uri
      headers: {
        Authorization: "Bearer #{@config.oauth.access}"
      }
      jar:null
      json:true
    }
    if body?
      params.body = body
    response = null
    request[method](params).on("response",((r)=>response = r)).on("end", ()=>
      if /^(4|5)[0-9][0-9]$/.test "#{response?.statusCode}"
        callback(new Error("Error status code returned (#{response.statusCode}) for URI #{uri}",response.statusCode,response))
      else
        callback(null,response?.statusCode,response)
    ).on("error",(err)=>
      callback(err,response?.statusCode,response)
    ).pipe(stream)

  interactive_add_note:(type,callback)=>
    rl = make_readline { input: process.stdin, output: process.stdout }
    rl.question "Title: ", (title)=>
      rl.question "Tags: ", (tags)=>
        rl.multiline "Body", (body)=>
          console.log title, tags.split(','), body
          callback()

  main:()=>
    @read_config ()=>
      switch process.argv[2]

        # HTTP VERBS
        when 'GET','get','POST','post','PUT','put','PATCH','patch','OPTIONS','options','HEAD','head','DELETE','delete','DEL','del'
          method = process.argv[2].toLowerCase()
          if method is 'delete'
            method = 'del'
          url = process.argv[3]
          url = @abs(url)
          body = process.argv[4]
          if body? and /^\s*[\"\{\[]/.test body
            body = JSON.parse(body)
          @ensure_access_token (err,success)=>
            @_request method, url, body, process.stdout, (err,sc,response)=>
              if err?
                console.error "ERROR:",err
                process.exit(2)
              else unless /^2[0-9][0-9]$/.test "#{sc}"
                console.error "WARNING: Non 2xx-series status code (#{sc})."
              process.exit(0)

        # LOGIN
        when 'login'
          delete @config.oauth.access
          delete @config.oauth.refreshed
          delete @config.oauth.refresh
          @ensure_active_access_token (err,success)=>
            if not err? and success
              process.exit(0)
            else
              console.error "ERROR: Unable to log in.\n"
              process.exit(2)

        # LOGOUT
        when 'logout'
          delete @config.oauth.access
          delete @config.oauth.refreshed
          delete @config.oauth.refresh
          @write_config (err)=>
            if err?
              process.exit(2)
            else
              process.exit(0)

        when 'select'
          @ensure_active_access_token ()=>
            @config.current ?= {}
            if process.argv[3] in ['org','workspace','note','task']
              @choose_org (err,org_id)=>
                @config.current.org_id = org_id
                if process.argv[3] in ['workspace','note','task']
                  @choose_workspace org_id,(err,workspace_id)=>
                    @config.current.workspace_id = workspace_id
                    if process.argv[3] in ['note','task']
                      @choose_note org_id,workspace_id,process.argv[3],(err,note_id)=>
                        @config.current.note_id = note_id
                        @write_config ()=>process.exit(0)
                    else
                      @write_config ()=>process.exit(0)
                else
                  @write_config ()=>process.exit(0)
            else
              console.error "Not recognized: ",process.argv[2..process.argv.length].join(' ')

        # ADD NOTE/TASK
        when '+note','+task'
          @interactive_add_note process.argv[2].substring(1),(err)=>
            if err?
              console.error "ERROR:",err
              process.exit(2)
            else
              process.exit(0)

        # VERSION
        when '--version', '-v'
          pkg = require(path.join(__dirname,'..','package.json'))
          console.log "#{pkg.name} #{pkg.version}"
          process.exit 0

        # HELP OR ERROR
        else
          console.log "USE: intellinote login|logout|(GET|POST|PUT|PATCH|DELETE|HEAD <URL> [<BODY>])"
          if /^((-?-?)|\/)?(h(elp)?)|\?$/i.test process.argv[2]
            process.exit 0
          else
            process.exit 1

exports.Intellinote = Intellinote

if require.main is module
  (new Intellinote()).main()
