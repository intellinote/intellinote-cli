# TODO - refactor for DRYness
# TODO - rationalize command line parameters
# TODO - unit (or at least functional) tests
# TODO - update use instructions
# TODO - consider https://www.npmjs.com/package/chalk
# TODO - extract readline extensions into inote-util (?)

readline = require 'readline'
fs       = require 'fs'
path     = require 'path'
request  = require 'request'
TermList = require 'term-list'

TILDE = process.env.HOME || process.env.HOMEPATH || process.env.USERPROFILE
CONFIG_FILE = path.join(TILDE,'.intellinote')
REFRESH_ACCESS_TOKEN_AFTER = 15*60*1000

HELP =  """
USE:
  intellinote ACTION
where ACTION is
  list orgs
    - to view a list of available orgs
  list workspaces in org <ORG-ID>
    - to view a list of available workspaces
  list notes|tasks in workspace <WORKSPACE-ID> [in org <ORG-ID>]
    - to view a list of available notes or tasks
  list attachments in note|task <NOTE-ID> [in workspace <WORKSPACE-ID> in org <ORG-ID>]
    - to view a list of available attachments
  fetch org <ORG-ID>
    - to retrieve the specified org
  fetch workspace <WORKSPACE-ID> [in org <ORG-ID>]
    - to retrieve the specified workspace
  fetch note|task <NOTE-ID> [in workspace <WORKSPACE-ID> in org <ORG-ID>]
    - to retrieve the specified note or task
  fetch attachment <ATTACHMENT-ID> [in note|task <NOTE-ID> [in workspace <WORKSPACE-ID> in org <ORG-ID>]]
    - to retrieve the specified attachment
  get org|workspace|note|task|attachment
    - to fetch an interactively selected object
  +task|+note
    - to interactively create a task or note
  -X GET|POST|PUT|PATCH|DELETE|HEAD <URL> [<BODY-AS-JSON-STRING>]
    - to execute an arbitrary REST method
  login
    - to log in
  logout
    - to log out
  ping
    - to test your connection to the server
  --version
    - to see version information
  --help
    - to see this message
"""

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
      followRedirect:false
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

  ping:(callback)=>
    @http "get", "/v2.0/ping/authed", callback

  ping_ok:(callback)=>
    @ping (err,sc,body,response,params)=>
      success = (not err?) and (/^2[0-9][0-9]$/.test "#{sc}") and (body?.timestamp?)
      callback( success )

  ensure_access_token:(callback)=>
    if @config.oauth?.access? and @config.oauth?.refreshed? and (Date.now() - @config.oauth.refreshed) < REFRESH_ACCESS_TOKEN_AFTER
      callback(null,true)
    else
      delete @config.oauth?.access
      delete @config.oauth?.refreshed
      @ensure_active_access_token(callback)

  ensure_active_access_token:(callback)=>
    if @config.oauth?.access?                                                 # if we already have an access token...
      @ping_ok (success)=>                                                    # ...test it...
        if success                                                            # ......on success, return `true`.
          callback null, true
        else                                                                  # ......on failure, delete that access token and try again.
          delete @config.oauth.access
          @ensure_active_access_token(callback)
    else if @config.oauth?.refresh?                                           # else if we already have a refresh token...
      @get_access_token (err)=>                                               # ...use it to get a new access token...
        @ping_ok (success)=>                                                  # ......test it...
          if success                                                          # .........on success, write the access token to the config and return `true`.
            @write_config (err)=>
              callback null, true
          else                                                                # .........on failure, delete the refresh token and try again.
            delete @config.oauth.refresh
            @ensure_active_access_token(callback)                             #
    else                                                                      # else when we have neither access nor refresh token...
      @get_credentials (err,u,p)=>                                            # ...ask the user for username and password...
        if err?
          @exit_error "Error getting credentials (#{err})"
        @get_refresh_token u,p,(err)=>                                        # ......use them to obtain a refresh token...
          if err?
            @exit_error "Error getting refresh token (#{err})"
          @get_access_token (err)=>                                           # .........use that to obtain an access token...
            if err?
              @exit_error "Error getting access token (#{err})"
            @ping_ok (success)=>                                              # ......test it...
              if success                                                      # .........on success, write the refresh and access tokens to the config and return `true`.
                @write_config (err)=>
                  callback null, true
              else                                                            # .........on failure, report failure to caller.
                callback(new Error("Unable to obtain an access token"),false)

  choose_org:(callback)=>
    @list_orgs (err,orgs)=>
      if err?
        callback(err)
      else if orgs.length is 0
        console.error "No matching orgs."
        callback(new Error( "No matching orgs."))
      else
        options = []
        for org,i in orgs
          options.push [org.org_id,"#{org.name} (#{org.org_id})"]
        dflt = @config?.current?.org_id
        @_menu "Choose Org",options,dflt,(err,org_id)=>
          if err?
            callback(err)
          else
            @config.current ?= {}
            unless org_id is @config.current.org_id
              delete @config.current.workspace_id
              delete @config.current.note_id
            @config.current.org_id = org_id
            callback(null,org_id)

  choose_workspace:(org_id,callback)=>
    @list_workspaces org_id,(err,workspaces)=>
      if err?
        callback(err)
      else if workspaces.length is 0
        console.error "No matching workspaces."
        callback(new Error( "No matching workspaces."))
      else
        options = []
        for workspace,i in workspaces
          options.push [workspace.workspace_id,"#{workspace.name} (#{workspace.workspace_id})"]
        dflt = @config?.current?.workspace_id
        @_menu "Choose Workpace",options,dflt,(err,workspace_id)=>
          if err?
            callback(err)
          else
            @config.current ?= {}
            unless workspace_id is @config.current.workspace_id
              delete @config.current.note_id
            @config.current.workspace_id = workspace_id
            callback(null,workspace_id)

  choose_note:(org_id,workspace_id,note_type,callback)=>
    @list_notes org_id,workspace_id,note_type,(err,notes)=>
      if err?
        callback(err)
      else if notes.length is 0
        console.error "No matching #{note_type ? 'note'}s"
        callback(new Error("No matching #{note_type ? 'note'}s"))
      else
        options = []
        for note,i in notes
          options.push [note.note_id,"#{(note.title ? '<untitled>').trim()} (#{note.note_id})"]
        dflt = @config?.current?.note_id
        if note_type is 'task'
          prompt = 'Task'
        else
          prompt = 'Note'
        @_menu "Choose #{prompt}",options,dflt,(err,note_id)=>
          if err?
            callback(err)
          else
            @config.current ?= {}
            @config.current.note_id = note_id
            callback(null,note_id)

  choose_attachment:(org_id,workspace_id,note_id,callback)=>
    @list_attachments org_id,workspace_id,note_id,(err,attachments)=>
      if err?
        callback(err)
      else if attachments.length is 0
        console.error "No matching attachmentss"
        callback(new Error("No matching attachments"))
      else
        options = []
        for attachment,i in attachments
          label = attachment.filename
          if attachment.mime_type
            label += " <#{attachment.mime_type}>"
          label += " (#{attachment.attachment_id})"
          options.push [attachment.attachment_id,label]
        @_menu "Choose Attachment",options,null,(err,attachment_id)=>
          if err?
            callback(err)
          else
            callback(null,attachment_id)

  list_orgs:(callback)=>
    @http 'get', "/v2.0/orgs", (err,sc,body)=>
      callback(err,body)

  list_workspaces:(org_id,callback)=>
    @http 'get', "/v2.0/org/#{org_id}/workspaces", (err,sc,body)=>
      callback(err,body)

  list_notes:(org_id,workspace_id,note_type,callback)=>
    url = "/v2.0/org/#{org_id}/workspace/#{workspace_id}/notes"
    if note_type?
      url += "?note_type=#{note_type}"
    @http 'get', url, (err,sc,body)=>
      callback(err,body)

  list_attachments:(org_id,workspace_id,note_id,callback)=>
    @http 'get', "/v2.0/org/#{org_id}/workspace/#{workspace_id}/note/#{note_id}/attachments", (err,sc,body)=>
      callback(err,body)

  _menu:(prompt,choices,dflt_key,callback)=>
    unless choices?.length > 0
      callback(null,null)
    else
      console.log prompt
      # list = new TermList(({ marker: '\x1b[36m› \x1b[0m', markerLength: 2 }))
      list = new TermList()
      for choice,i in choices
        key = choice[0]
        label = choice[1]
        list.add key, label
      if dflt_key?
        list.select(dflt_key)
      list.on 'keypress', (key, item)->
        switch key.name
          when 'return'
            list.stop()
            callback(null,item)
      list.start()

  http:(method,uri,body,callback)=>
    params = {
      url:@abs(uri)
      headers: { Authorization: "Bearer #{@config.oauth.access}" }
      jar:null
      json:true
    }
    if (typeof body is 'function') and not callback?
      callback = body
      body = null
    if body?
      params.body = body
    request[method] params, (err,response,body)=>
      sc = response?.statusCode
      unless err? or /^2[0-9][0-9]$/.test sc
        err = new Error("Non-2xx-series status code (#{sc})")
      callback(err,sc,body,response,params)

  stream_http:(method,uri,body,stream,callback)=>
    params = {
      url:@abs(uri)
      headers: { Authorization: "Bearer #{@config.oauth.access}" }
      jar:null
      json:true
    }
    if body?
      params.body = body
    response = null
    request[method](params).on("response",((r)=>response = r)).on("end", ()=>
      sc = response?.statusCode
      err = null
      unless /^2[0-9][0-9]$/.test sc
        err = new Error("Non-2xx-series status code (#{sc})")
      callback(err,sc,stream,response,params)
    ).on("error",(err)=>
      callback(err,response?.statusCode,stream,response,params)
    ).pipe(stream)

  interactive_add_note:(type,callback)=>
    rl = make_readline { input: process.stdin, output: process.stdout }
    rl.question "Title: ", (title)=>
      rl.question "Tags: ", (tags)=>
        if tags?
          tags = tags.split ','
        else
          tags = []
        tags = tags.map((t)->{label:t})
        rl.multiline "Body", (body)=>
          @choose_org (err,org_id)=>
            if err?
              callback err
            else
              @choose_workspace org_id,(err,workspace_id)=>
                if err?
                  callback err
                else
                  payload = {
                    note_type: type.toUpperCase()
                    title:title
                    body:body
                    tags:tags
                  }
                  @post_note org_id, workspace_id, payload, callback

  post_note:(org_id,workspace_id,payload,callback)=>
    params = {
      url:@abs("/v2.0/org/#{org_id}/workspace/#{workspace_id}/note")
      headers: { Authorization: "Bearer #{@config.oauth.access}" }
      jar:null
      json:true
      body: payload
    }
    request.post params, (err,response,body)=>
      if err?
        callback(err)
      else unless /^2[0-9][0-9]$/.test "#{response?.statusCode}"
        callback(new Error("Non-2xx-series status code (#{response?.statusCode})"))
      else
        callback null,body

  exit_error:(message,exit_code=1)=>
    console.error "ERROR:",message
    process.exit(exit_code)

  exit_success:(message)=>
    if message?
      console.log message
    console.log ""
    process.exit(0)

  cmd_http:(method,url,body)=>
    m = method?.toLowerCase()
    unless m in ['get','post','put','patch','options','head','delete']
      @exit_error "Unrecognized HTTP verb #{method}"
    else
      m = 'del' if m is 'delete'
      if body? and /^\s*[\"\{\[]/.test body
        try
          body = JSON.parse(body)
        catch err
          @exit_error "Error parsing body as JSON string: #{err}"
       @ensure_access_token (err,success)=>
         if err? or !success
           @exit_error "Unable to obtain access token (#{err})."
         else
           @stream_http m, url, body, process.stdout, (err,sc,s,response,p)=>
             if err?
               @exit_error "Error executing #{method} #{url} (#{err})."
             else
               @exit_success()

  clear_oauth:()=>
    if @config?.oauth?
      delete @config.oauth.access
      delete @config.oauth.refreshed
      delete @config.oauth.refresh

  _parse_ins:(args)=>
    result = {}
    for i in [0...args.length-2]
      if args[i] is "in" and args[i+2]?
        if args[i+1] in ["org","organization"]
          result.org_id = args[i+2]
        else if args[i+1] in ["workspace","ws"]
          result.workspace_id = args[i+2]
        else if args[i+1] in ["note","task"]
          result.note_id = args[i+2]
    return result

  main:()=>
    try
      @read_config ()=>
        switch process.argv[2]

          # HTTP
          when "-X","HTTP","HTTPS"
            @cmd_http(process.argv.slice(3)...)

          # LIST
          when "list"
            if process.argv.length > 3
              ctx = @_parse_ins process.argv.slice(4)
            switch process.argv[3]
              when "orgs"
                @cmd_http "GET","/v2.0/orgs"
              when "workspaces"
                unless ctx.org_id?
                  @exit_error "Expected 'in org <ORG-ID>' in: #{process.argv.slice(2).join(' ')}"
                else
                  @cmd_http "GET","/v2.0/org/#{ctx.org_id}/workspaces"
              when "notes","tasks"
                unless ctx.workspace_id?
                  @exit_error "Expected 'in workspace <WORKSPACE-ID> [in org <ORG-ID>]' in: #{process.argv.slice(2).join(' ')}"
                else if ctx.org_id? and ctx.workspace_id?
                  @cmd_http "GET","/v2.0/org/#{ctx.org_id}/workspace/#{ctx.workspace_id}/notes?type=#{process.argv[3].substring(0,4)}"
                else
                  @cmd_http "GET","/v2.0/workspace/#{ctx.workspace_id}/notes?type=#{process.argv[3].substring(0,4)}"
              when "attachments"
                if ctx.org_id? and ctx.workspace_id? and ctx.note_id?
                  @cmd_http "GET","/v2.0/org/#{ctx.org_id}/workspace/#{ctx.workspace_id}/note/#{ctx.note_id}/attachments"
                else
                  @cmd_http "GET","/v2.0/note/#{ctx.note_id}/attachments"
              else
                @exit_error "Unrecognized action: #{process.argv.slice(2).join(' ')}"

          # FETCH
          when "fetch"
            if process.argv.length > 4
              ctx = @_parse_ins process.argv.slice(5)
            switch process.argv[3]
              when "org","organization"
                unless process.argv[4]?
                  @exit_error "Expected 'org <ORG-ID>' in: #{process.argv.slice(2).join(' ')}"
                else
                  @cmd_http "GET","/v2.0/org/#{process.argv[4]}"
              when "workspace","ws"
                unless process.argv[4]?
                  @exit_error "Expected 'workspace <WORKSPACE-ID>' in: #{process.argv.slice(2).join(' ')}"
                else
                  @cmd_http "GET","/v2.0/workspace/#{process.argv[4]}"
              when "note","task"
                unless process.argv[4]?
                  @exit_error "Expected 'note <NOTE-ID>' or 'task <TASK-ID>' in: #{process.argv.slice(2).join(' ')}"
                else
                  @cmd_http "GET","/v2.0/note/#{process.argv[4]}"
              when "attachment"
                unless process.argv[4]?
                  @exit_error "Expected 'attachment <ATTACHMENT-ID>' in: #{process.argv.slice(2).join(' ')}"
                else
                  @cmd_http "GET","/v2.0/attachment/#{process.argv[4]}"
              else
                @exit_error "Unrecognized action: #{process.argv.slice(2).join(' ')}"

          # PING
          when '--ping','ping'
            @ensure_active_access_token (err,success)=>
              if err? or !success
                @exit_error "Unable to obtain access token (#{err})."
              else
                @ping (err,sc,body,response,params)=>
                  if err?
                    console.error params
                    @exit_error err
                  else
                    @exit_success JSON.stringify(body)

          # LOGIN
          when 'login'
            @clear_oauth()
            @ensure_active_access_token (err,success)=>
              if err?
                @exit_error err
              else if not success
                @exit_error "Unable to obtain access token."
              else
                @exit_success()

          # LOGOUT
          when 'logout'
            @clear_oauth()
            @write_config (err)=>
              if err?
                @exit_error "Unable to re-write configuration file at #{CONFIG_FILE} (#{err})."
              else
                @exit_success()

          when 'set'
            @ensure_active_access_token ()=>
              @config.current ?= {}
              if process.argv[3] in ['org','workspace','note','task']
                @choose_org (err,org_id)=>
                  if process.argv[3] in ['workspace','note','task']
                    @choose_workspace org_id,(err,workspace_id)=>
                      if process.argv[3] in ['note','task']
                        @choose_note org_id,workspace_id,process.argv[3],(err,note_id)=>
                          @write_config ()=>process.exit(0)
                      else
                        @write_config ()=>process.exit(0)
                  else
                    @write_config ()=>process.exit(0)
              else
                console.error "Not recognized: ",process.argv[2..process.argv.length].join(' ')

          when 'get'
            @ensure_active_access_token ()=>
              @config.current ?= {}
              if process.argv[3] in ['org','workspace','note','task','attachment']
                @choose_org (err,org_id)=>
                  if err?
                    @exit_error err
                  else
                    if process.argv[3] in ['workspace','note','task','attachment']
                      @choose_workspace org_id,(err,workspace_id)=>
                        if err?
                          @exit_error err
                        else
                          if process.argv[3] in ['note','task','attachment']
                            note_type = null
                            if process.argv[3] in ['note','task']
                              note_type = process.argv[3]
                            @choose_note org_id,workspace_id,note_type,(err,note_id)=>
                              if err?
                                @exit_error err
                              else
                                if process.argv[3] in ['attachment']
                                  @choose_attachment org_id,workspace_id,note_id,(err,attachment_id)=>
                                    if err?
                                      @exit_error err
                                    else
                                      @cmd_http "GET","/v2.0/org/#{org_id}/workspace/#{workspace_id}/note/#{note_id}/attachment/#{attachment_id}"
                                else
                                  @cmd_http "GET","/v2.0/org/#{org_id}/workspace/#{workspace_id}/note/#{note_id}"
                          else
                            @cmd_http "GET","/v2.0/org/#{org_id}/workspace/#{workspace_id}"
                    else
                      @cmd_http "GET","/v2.0/org/#{org_id}"
              else
                console.error "Not recognized: ",process.argv[2..process.argv.length].join(' ')
                process.exit(1)

          # ADD NOTE/TASK
          when '+note','+task'
            @ensure_active_access_token ()=>
              @interactive_add_note process.argv[2].substring(1),(err,response)=>
                if err?
                  console.error "ERROR:",err
                  process.exit(2)
                else
                  console.log "Created",response
                  @write_config ()=>process.exit(0)

          # VERSION
          when '--version', '-v'
            pkg = require(path.join(__dirname,'..','package.json'))
            @exit_success "#{pkg.name} #{pkg.version}"


          # HELP OR ERROR
          else
            if /^((-?-?)|\/)?(h(elp)?)|\?$/i.test process.argv[2]
              @exit_success HELP
            else
              @exit_error HELP
    catch err
      @exit_error "Uncaught exception #{err}"

exports.Intellinote = Intellinote

if require.main is module
  (new Intellinote()).main()


# THIS VERSION OF _menu USES A SIMPLE TEXT MENU INSTEAD OF node-term-list
  # _menu:(prompt,choices,dflt_key,callback)=>
  #   unless choices?.length > 0
  #     callback(null,null)
  #   else
  #     dflt_index = 1
  #     console.log prompt
  #     for choice,i in choices
  #       key= choice[0]
  #       label = choice[1]
  #       console.log "  [#{i+1}] #{label}"
  #       if key is dflt_key
  #         dflt_index = i+1
  #     rl = make_readline { input: process.stdin, output: process.stdout }
  #     rl.question "[#{dflt_index}]> ", (selection)=>
  #       if /^\s*$/.test selection
  #         selection = dflt_index
  #       else if /^\s*[0-9]\s*$/.test selection
  #         selection = parseInt(selection)
  #       rl.close()
  #       unless 1 <= selection <= choices.length
  #         console.log "\nNot Valid\n"
  #         @_menu(prompt,choices,dflt_key,callback)
  #       else
  #         callback(null,choices[selection-1][0])
