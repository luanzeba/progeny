require 'posix/spawn/version'
require 'posix/spawn/child'

module POSIX
  module Spawn
    extend self

    # Spawn a child process with a variety of options using the best
    # available implementation for the current platform and Ruby version.
    #
    # spawn([env], command, [argv1, ...], [options])
    #
    # env     - Optional hash specifying the new process's environment.
    # command - A string command name, or shell program, used to determine the
    #           program to execute.
    # argvN   - Zero or more string program arguments (argv).
    # options - Optional hash of operations to perform before executing the
    #           new child process.
    #
    # Returns the integer pid of the newly spawned process.
    # Raises any number of Errno:: exceptions on failure.
    def spawn(*args)
      ::Process::spawn(*args)
    end

    # Spawn a child process with all standard IO streams piped in and out of
    # the spawning process. Supports the standard spawn interface as described
    # in the POSIX::Spawn module documentation.
    #
    # Returns a [pid, stdin, stdout, stderr] tuple, where pid is the new
    # process's pid, stdin is a writeable IO object, and stdout / stderr are
    # readable IO objects. The caller should take care to close all IO objects
    # when finished and the child process's status must be collected by a call
    # to Process::waitpid or equivalent.
    def popen4(*argv)
      # create some pipes (see pipe(2) manual -- the ruby docs suck)
      ird, iwr = IO.pipe
      ord, owr = IO.pipe
      erd, ewr = IO.pipe

      # spawn the child process with either end of pipes hooked together
      opts =
        ((argv.pop if argv[-1].is_a?(Hash)) || {}).merge(
          # redirect fds        # close other sides
          :in  => ird,          iwr  => :close,
          :out => owr,          ord  => :close,
          :err => ewr,          erd  => :close
        )
      pid = spawn(*(argv + [opts]))

      [pid, iwr, ord, erd]
    ensure
      # we're in the parent, close child-side fds
      [ird, owr, ewr].each { |fd| fd.close if fd }
    end

    ##
    # Process::Spawn::Child Exceptions

    # Exception raised when the total number of bytes output on the command's
    # stderr and stdout streams exceeds the maximum output size (:max option).
    # Currently
    class MaximumOutputExceeded < StandardError
    end

    # Exception raised when timeout is exceeded.
    class TimeoutExceeded < StandardError
    end

    private

    # Turns the various varargs incantations supported by Process::spawn into a
    # simple [env, argv, options] tuple. This just makes life easier for the
    # extension functions.
    #
    # The following method signature is supported:
    #   Process::spawn([env], command, ..., [options])
    #
    # The env and options hashes are optional. The command may be a variable
    # number of strings or an Array full of strings that make up the new process's
    # argv.
    #
    # Returns an [env, argv, options] tuple. All elements are guaranteed to be
    # non-nil. When no env or options are given, empty hashes are returned.
    def extract_process_spawn_arguments(*args)
      # pop the options hash off the end if it's there
      options =
        if args[-1].respond_to?(:to_hash)
          args.pop.to_hash
        else
          {}
        end
      flatten_process_spawn_options!(options)
      normalize_process_spawn_redirect_file_options!(options)

      # shift the environ hash off the front if it's there and account for
      # possible :env key in options hash.
      env =
        if args[0].respond_to?(:to_hash)
          args.shift.to_hash
        else
          {}
        end
      env.merge!(options.delete(:env)) if options.key?(:env)

      # remaining arguments are the argv supporting a number of variations.
      argv = adjust_process_spawn_argv(args)

      [env, argv, options]
    end

    # Convert { [fd1, fd2, ...] => (:close|fd) } options to individual keys,
    # like: { fd1 => :close, fd2 => :close }. This just makes life easier for the
    # spawn implementations.
    #
    # options - The options hash. This is modified in place.
    #
    # Returns the modified options hash.
    def flatten_process_spawn_options!(options)
      options.to_a.each do |key, value|
        if key.respond_to?(:to_ary)
          key.to_ary.each { |fd| options[fd] = value }
          options.delete(key)
        end
      end
    end

    # Mapping of string open modes to integer oflag versions.
    OFLAGS = {
      "r"  => File::RDONLY,
      "r+" => File::RDWR   | File::CREAT,
      "w"  => File::WRONLY | File::CREAT  | File::TRUNC,
      "w+" => File::RDWR   | File::CREAT  | File::TRUNC,
      "a"  => File::WRONLY | File::APPEND | File::CREAT,
      "a+" => File::RDWR   | File::APPEND | File::CREAT
    }

    # Convert variations of redirecting to a file to a standard tuple.
    #
    # :in   => '/some/file'   => ['/some/file', 'r', 0644]
    # :out  => '/some/file'   => ['/some/file', 'w', 0644]
    # :err  => '/some/file'   => ['/some/file', 'w', 0644]
    # STDIN => '/some/file'   => ['/some/file', 'r', 0644]
    #
    # Returns the modified options hash.
    def normalize_process_spawn_redirect_file_options!(options)
      options.to_a.each do |key, value|
        next if !fd?(key)

        # convert string and short array values to
        if value.respond_to?(:to_str)
          value = default_file_reopen_info(key, value)
        elsif value.respond_to?(:to_ary) && value.size < 3
          defaults = default_file_reopen_info(key, value[0])
          value += defaults[value.size..-1]
        else
          value = nil
        end

        # replace string open mode flag maybe and replace original value
        if value
          value[1] = OFLAGS[value[1]] if value[1].respond_to?(:to_str)
          options[key] = value
        end
      end
    end

    # The default [file, flags, mode] tuple for a given fd and filename. The
    # default flags vary based on the what fd is being redirected. stdout and
    # stderr default to write, while stdin and all other fds default to read.
    #
    # fd   - The file descriptor that is being redirected. This may be an IO
    #        object, integer fd number, or :in, :out, :err for one of the standard
    #        streams.
    # file - The string path to the file that fd should be redirected to.
    #
    # Returns a [file, flags, mode] tuple.
    def default_file_reopen_info(fd, file)
      case fd
      when :in, STDIN, $stdin, 0
        [file, "r", 0644]
      when :out, STDOUT, $stdout, 1
        [file, "w", 0644]
      when :err, STDERR, $stderr, 2
        [file, "w", 0644]
      else
        [file, "r", 0644]
      end
    end

    # Determine whether object is fd-like.
    #
    # Returns true if object is an instance of IO, Integer >= 0, or one of the
    # the symbolic names :in, :out, or :err.
    def fd?(object)
      case object
      when Integer
        object >= 0
      when :in, :out, :err, STDIN, STDOUT, STDERR, $stdin, $stdout, $stderr, IO
        true
      else
        object.respond_to?(:to_io) && !object.to_io.nil?
      end
    end

    # Convert a fd identifier to an IO object.
    #
    # Returns nil or an instance of IO.
    def fd_to_io(object)
      case object
      when STDIN, STDOUT, STDERR, $stdin, $stdout, $stderr
        object
      when :in, 0
        STDIN
      when :out, 1
        STDOUT
      when :err, 2
        STDERR
      when Integer
        object >= 0 ? IO.for_fd(object) : nil
      when IO
        object
      else
        object.respond_to?(:to_io) ? object.to_io : nil
      end
    end

    # Derives the shell command to use when running the spawn.
    #
    # On a Windows machine, this will yield:
    #   [['cmd.exe', 'cmd.exe'], '/c']
    # Note: 'cmd.exe' is used if the COMSPEC environment variable
    #   is not specified. If you would like to use something other
    #   than 'cmd.exe', specify its path in ENV['COMSPEC']
    #
    # On all other systems, this will yield:
    #   [['/bin/sh', '/bin/sh'], '-c']
    #
    # Returns a platform-specific [[<shell>, <shell>], <command-switch>] array.
    def system_command_prefixes
      if RUBY_PLATFORM =~ /(mswin|mingw|cygwin|bccwin)/
        sh = ENV['COMSPEC'] || 'cmd.exe'
        [[sh, sh], '/c']
      else
        [['/bin/sh', '/bin/sh'], '-c']
      end
    end

    # Converts the various supported command argument variations into a
    # standard argv suitable for use with exec. This includes detecting commands
    # to be run through the shell (single argument strings with spaces).
    #
    # The args array may follow any of these variations:
    #
    # 'true'                     => [['true', 'true']]
    # 'echo', 'hello', 'world'   => [['echo', 'echo'], 'hello', 'world']
    # 'echo hello world'         => [['/bin/sh', '/bin/sh'], '-c', 'echo hello world']
    # ['echo', 'fuuu'], 'hello'  => [['echo', 'fuuu'], 'hello']
    #
    # Returns a [[cmdname, argv0], argv1, ...] array.
    def adjust_process_spawn_argv(args)
      if args.size == 1 && args[0].is_a?(String) && args[0] =~ /[ |>]/
        # single string with these characters means run it through the shell
        command_and_args = system_command_prefixes + [args[0]]
        [*command_and_args]
      elsif !args[0].respond_to?(:to_ary)
        # [argv0, argv1, ...]
        [[args[0], args[0]], *args[1..-1]]
      else
        # [[cmdname, argv0], argv1, ...]
        args
      end
    end
  end
end
