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

  end
end
