{ term: terminal } =
_ = require './utilities.coffee'


# TODO: I'd really like to extract most of this into npm modules. It represents a lot of thought and
#       work, and is mostly inspecific to Paws. Several things here are ripe for generalization: the
#       `infect` mechanism; `verbosities`, and most interestingly, `ENV`. They're all fairly
#       inter-dependant, but I suspect that can be remedied / accommodated.
# NOTE: ENV *could* be in `utilities`, because it's more generally-applicable than just to debugging
#       in the usual case; but in this codebase, I want to encourage the ‘ENV variables are for
#       debugging; command-line flags or API calls are for operational configuration’ convention.
#       Hence, restricting the ENV behaviour to the debugging module.

              #    0       1      2       3      4      5     6     7      8     9
verbosities = "emergency alert critical error warning notice info debug verbose wtf".split(' ')

module.exports = debugging =

   # This is an exposed, bi-directional mapping of verbosity-names:
   #
   #     debugging.verbosities[4] = 'warning'
   #     debugging.verbosities['warning'] = 4
   verbosities: do ->
      $ = verbosities.slice()
      $[name] = minimum for name, minimum in $
      $

   verbosity: -> debugging.VERBOSE()
   is_silent: -> debugging.VERBOSE() == 0


   # If called, (re-)configures this debugging system for either a DOM-based (`browser`) or
   # UNIX-based (`CLI`) environment.
   init: do ->
      $init = (environment)->
         environment ?= if process?.browser? then 'browser' else 'CLI'

         $init[environment]()

      $init.CLI = (stream = process.stderr)->
         _.extend debugging,
            _environment:  'CLI'
            has_terminal: yes
            has_browser:  no

            log: ->
               output = _.node.format.apply(_.node, arguments) + '\n'
               stream.write output, 'utf8'

         # XXX: Yes, `Paws.colour()` is intentionally not defined unless executing at the CLI. You
         #      shouldn't be checking `COLOUR` unless you're about to add ANSI codes, and you
         #      shouldn't be about to add ANSI codes unless you've checked `has_terminal`.
         debugging.ENV ['COLOUR', 'COLOR'], value: true, infect: true
         debugging.ENV 'SIMPLE_ANSI', value: false

      $init.browser = (window = window, console = console)->
         _.extend debugging,
            _environment: 'browser'
            has_terminal: no
            has_browser:  yes

            log: ->
               _.bind (console?.error || console?.log || noop), console

      return $init


   infect: do ->
      virii = new Array
      infectees = new Array

      infect = (target)->
         infectees.push target
         target[member] = debugging[member] for member in virii

      infect.add = (members...)->
         virii.push members...
         for target in infectees
            target[member] = debugging[member] for member in members

      return infect


   # The debugging system is largely powered by UNIX environment-variables, because these are
   # equally accessible even whether Paws.js is used from the command-line, or loaded as a library.
   #
   # To this end, at load-time, we read in variables we know we need, and expose them as read-only
   # or overridable herein. In addition, some of these are further exposed on ‘injectees’ (for
   # instance, the `Paws` namespace throughout this codebase.)
   #
   # ----
   #
   # Defining a new envar / setting with this function accepts a name (or a list of aliases), and a
   # set of options for that setting:
   #
   #  - `type:` One of `'string', 'number', 'boolean'`; describes how values for the setting will be
   #    parsed when set (since all envars are string-ish.)
   #  - `value:` A default value for the setting, if not set.
   #  - `handler:` A custom function to interpret the string-ish envar into a JavaScript value for
   #    the setting in question. If `type` is *also* specified, then the `handler` receives the
   #    pre-parsed data.
   #  - `immutable:` Can be set to true, preventing this setting from being modified
   #    programmatically after load-time. (i.e. ‘environment overrides API.’)
   #  - `infect:` Whether or not `debugging.infect` will expose this setting on infectees (i.e. the
   #    `Paws` export.) The settings are *always* exposed on the `debugging` object, either way.
   #
   # All are optional. Without any set, `ENV` simply creates a new boolean setting that defaults to
   # `false`:
   #
   #     debugging.ENV 'FRIENDLY'
   #     debugging.friendly()    #-> no
   #     debugging.friendly yes  #-> yes
   #
   # The `type` can be inferred from the default `value`, if provided; and both `immutable` and
   # `infect` default to no.
   #
   # The `handler`, meanwhile, if defined, will be passed the string-ish value from the UNIX
   # environment at load-time (if no `type` is explicitly given), or a pre-parsed version thereof
   # (if a `type` is given); and later the same for any values passed to the setters generated by
   # `ENV` (if the setting isn't `immutable`, of course.) Any value it returns will become the value
   # of the setting in question.
   #
   # In addition to the found/passed ‘new’ value for the option, the handler will be passed the
   # current (‘old’) value for the option, as well as the canonical name of the option (and, if
   # relevant, the alias under which the option was set.)
   #
   # If an array of `names` is provided, then they're treated as equivalent aliases: both accessing
   # and setting share a value for the setting in question, regardless of which name it's accessed
   # by.
   #
   #     debugging.ENV ['LOVE', 'FRIENDLINESS'], value: 1000
   #     debugging.love 1000000     #-> 1000000
   #     debugging.friendliness()   #-> 1000000
   #
   # When defining settings, case is unimportant; they're always read from the UNIX environment in
   # all-caps, and are always exposed in the API as lowercase.
   ENV: ENV = do ->
      $values = new Object

      (names, opt = {})->
         names       = [names] unless _.isArray names
         type        = opt.type      ? typeof opt.value || 'boolean'
         defavlt     = opt.value
         callback    = opt.handler
         immutable   = opt.immutable ? false
         infect      = opt.infect    ? false

         members     = names.map (n)-> n.toLowerCase()   # colour(), color()
         names       = names.map (n)-> n.toUpperCase()   # 'COLOUR', 'COLOR'
         key         = names[0]                          # 'COLOUR'

         debugging.verbose "-- Registering '#{key}' ENV-option" if debugging.verbose

         # deal with each type of string-ish value differently, but consistently. (the type is
         # automatically derived from the default value, unless explicitly specified)
         handler = switch type
            when 'string' then (str)-> str
            when 'number' then parse_numberish
            else               parse_booleanish

         if type is 'boolean'
            names.push ( _.map names, (name)-> 'NO'+name )...

         if callback
            handler = if opt.type? then ->
               handled = handler.apply null, arguments
               callback.call null, handled, _.rest(arguments)...
            else callback

         # immediately check each alias for values in the ENV to find an initial value; earlier
         # names for the setting override later ones
         if process?.env?
            _.forEach names.slice().reverse(), (name)-> if process.env[name]?
               $values[key] = handler process.env[name], $values[key], key, name

               if debugging.VERBOSE?() >= debugging.verbosities['verbose']
                  exists_as = if (name is key) then '' else " (as '#{name}')"
                  debugging.log "-- ENV-option '#{key}' present#{exists_as}: #{$values[key]}"

         if defavlt? and not $values[key]?
            $values[key] = defavlt

         # generate a wrapper-function that receives mutation arguments to env-functions and passes
         # them to the handler ascertained above
         wrapper_as = (as_name)->
            if immutable
               getter = -> $values[key]
            else
               setter = (arg)->
                  unless arg?
                     return $values[key]

                  result = handler arg, $values[key], key, as_name
                  $values[key] = result if result?

         debugging[member] = wrapper_as member for member in members
         debugging.infect.add members... if infect

         return debugging[members[0]]

parse_numberish  = (arg)->
   int = parseInt arg
   if isNaN int then undefined else int

parse_booleanish = (arg, braaaaiiins, braaaaaaaiiiiiinnns, as_name)->
   bool = if arg is false or /^[nf]/i.test arg.toString() then false
   else   if arg is true  or /^[yt]/i.test arg.toString() then true

   return null unless bool?
   return !bool if /^NO/.test as_name
   return bool


# The `VERBOSE` environment-variable and friends are handled specially: every `verbosities`-name in
# the environment is an alias to the same setting (hereafter referred to as `VERBOSE`). When set, if
# set to a numerical value, that value becomes the value of `VERBOSE`, regardless of the name by
# which it is set; however, if *not* numerical, then it's treated as a boolean, with the resultant
# value of `VERBOSE` depending on the truthiness thereof:
#
#  - If truthy, the `VERBOSE` level will be raised to *at least* the named level of verbosity;
#  - but if falsey, it will be *lowered* if it is *above* the named level.
#
# For instance, `debugging.verbose 6` will result in a debugging-verbosity of ‘info’; which could be
# alternatively set with `debugging.info true`. (As described for `ENV` above, these are
# configurable via UNIX envars; i.e. `VERBOSE=6` or `INFO=yahhuh!`.)
#
# In addition to the standard `verbosities`, I here include `QUIET` (2) and `SILENT` (0).
#
# **N.B.: By design, this mechanism will never *raise* a previously-configured verbosity.** The
# verbosity can be raised from the default, but never again via the API. (This means that you cannot
# programmatically override the command-line user's ‘be quiet!’ flags with the API. Sorrynotsorry.)
ENV _.union(verbosities, ['SILENT', 'QUIET']),
   value: 4
   handler: (value, current, name)->
      level = if (int = parse_numberish value)? then int
      else verbosities.indexOf name.toLowerCase()

      if level is -1 and name is 'SILENT' then level = 0
      if level is -1 and name is 'QUIET'  then level = 2

      # A bit of a hack; but `_environment` isn't set until `init()` is called, which is *after* the
      # UNIX environment is scanned above.
      if debugging._environment?
         if verbosity_set_at_load and current < level then current
         else                                              level
      else
         verbosity_set_at_load = yes
         level

verbosity_set_at_load = no

# We also set `VERBOSE`, `QUIET`, and `SILENT` aliases on infectees (notice the case, and contrast
# with `verbose` and friends, overriden below.)
_.extend debugging,
   VERBOSE: debugging.verbose
   QUIET:   debugging.quiet
   SILENT:  debugging.silent

debugging.infect.add 'VERBOSE', 'QUIET', 'SILENT'

# Finally, we create special aliases to `debugging.log`, for each of our `debugging.verbosities`,
# (for instance, `debugging.warning()` or `debugging.info`) with the caveat that each alias becomes
# a noop when the `ENV.verbose()` setting is lower than that verbosity.
#
# These override the default getter/setter functionality that `ENV` adds above (although that is
# preserved under capitalized names for `VERBOSE` etc; see above.)
#
# Of note, these are all set to `infect`; so they're exposed on `Paws` as well (i.e. `Paws.info()`.)
for name, this_level in verbosities
   do (name, this_level)->
      debugging[name] = ->
         debugging.log.apply debugging, arguments if this_level <= debugging.verbosity()

   debugging.infect.add name


debugging.init()
debugging.debug "++ Debugging available"
