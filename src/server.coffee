express = require 'express'
stylus = require 'stylus'
_ = require 'lodash'
fs = require 'fs'
path = require 'path'
runner = require './runner'
jobs = require './jobs'
git = require './git'
require 'express-namespace'

CHANGED_JSON_PATH = '/tmp/_concrete_changed.json'

authorize = (user, pass) ->
    user == git.user and pass == git.pass

if git.user and git.pass
    app = module.exports = express.createServer(express.basicAuth(authorize))
else
    app = module.exports = express.createServer()

app.helpers
  baseUrl: ->
    path.normalize("#{global.currentNamespace}/")

app.configure ->
    app.set 'views', __dirname + '/views'
    app.set 'quiet', yes
    # use coffeekup for html markup
    app.set 'view engine', 'coffee'
    app.register '.coffee', require('coffeekup').adapters.express
    app.set 'view options', {
        layout: false
    }

    # this must be BEFORE other app.use
    app.use stylus.middleware
        debug: false
        src: __dirname + '/views'
        dest: __dirname + '/public'
        compile: (str)->
            stylus(str).set 'compress', true

    coffeeDir = __dirname + '/views'
    publicDir = __dirname + @_locals.baseUrl() + '/public'
    app.use express.compiler src: coffeeDir, dest: publicDir, enable: ['coffeescript']

    app.use express.logger('short')
    app.use express.bodyParser()
    app.use app.router

    if process.env.LOG_FILE
      app.use '/log', express.static path.dirname(process.env.LOG_FILE)

    app.use global.currentNamespace, express.static __dirname + '/public'

app.configure 'development', ->
    app.use express.errorHandler dumpExceptions: on, showStack: on

app.configure 'production', ->
    app.use express.errorHandler dumpExceptions: on, showStack: on

deferredApp = ->
  app.get '/', (req, res) ->
      jobs.getAll (jobs)->
          res.render 'index',
              project: path.basename process.cwd()
              jobs: jobs
              logFile: ('log/' + path.basename(process.env.LOG_FILE)) if process.env.LOG_FILE
              mongoDB: process.env.CONCRETE_MONGODB

  app.get '/jobs', (req, res) ->
      jobs.getAll (jobs)->
          res.json jobs

  app.get '/job/:id', (req, res) ->
      jobs.get req.params.id, (job) ->
          res.json job

  app.get '/job/:id/:attribute', (req, res) ->
      jobs.get req.params.id, (job) ->
          if job[req.params.attribute]?
              # if req.xhr...
              res.json job[req.params.attribute]
          else
              res.send "The job doesn't have the #{req.params.attribute} attribute"

  app.get '/clear', (req, res) ->
      jobs.clear ->
          res.redirect "#{@_locals.baseUrl()}/jobs"

  app.get '/add', (req, res) ->
      jobs.addJob ->
          res.redirect "#{@_locals.baseUrl()}/jobs"

  app.get '/ping', (req, res) ->
      jobs.getLast (job) ->
          if job.failed
              res.send(412)
          else
              res.send(200)

  app.post '/', (req, res) ->
      try
        payload = JSON.parse(req.body.payload) if req.body.payload
      catch e
        
      jobs.addJob(
          (job)->
              runner.build()
              if req.xhr
                  console.log job
                  res.json job
              else
                  res.redirect "#{@_locals and @_locals.baseUrl()}/"
          payload)
if global.currentNamespace != "/"
  app.namespace global.currentNamespace, deferredApp
else
  deferredApp()
