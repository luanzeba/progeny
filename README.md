# progeny

Spawn child processes with simple string based standard input/output/error
stream handling in an easy-to-use interface.

## Progeny::Command

The `Progeny::Command` class includes logic for executing child processes and
reading/writing from their standard input, output, and error streams. It's
designed to take all input in a single string and provides all output as single
strings and is therefore not well-suited to streaming large quantities of data
in and out of commands. That said, it has some benefits:

 - **Simple** - requires little code for simple stream input and capture.
 - **Internally non-blocking** (using `select(2)`) - handles all pipe hang
   cases due to exceeding `PIPE_BUF` limits on one or more streams.
 - **Uses Ruby under the hood** - It leverages Ruby's `Process.spawn` behind
   the scenes so it's widely supported and consistently getting performance
   updates.

`Progeny::Command` takes the [standard `Process::spawn`
arguments](https://ruby-doc.org/current/Process.html#method-c-spawn) when
instantiated, and runs the process to completion after writing all input and
reading all output:

```ruby
require 'progeny'
child = Progeny::Command.new('git', '--help')
```

Retrieve process output written to stdout / stderr, or inspect the process's
exit status:

```ruby
child.out
# => "usage: git [--version] [--exec-path[=GIT_EXEC_PATH]]\n ..."
child.err
# => ""
child.status
# => #<Process::Status: pid=80718,exited(0)>
```

Use the `:input` option to write data on the new process's stdin immediately
after spawning:

```ruby
child = Progeny::Command.new('bc', :input => '40 + 2')
child.out
# => "42\n"
```

Additional options can be used to specify the maximum output size (`:max`) and
time of execution (`:timeout`) before the child process is aborted. See the
`Progeny::Command` docs for more info.

#### Reading Partial Results

`Progeny::Command` spawns the process immediately when instantiated.
As a result, if it is interrupted by an exception (either from reaching the
maximum output size, the time limit, or another factor), it is not possible to
access the `out` or `err` results because the constructor did not complete.

If you want to get the `out` and `err` data that was available when the process
was interrupted, use the `Progeny::Command` alternate form to create the child
without immediately spawning the process.  Call `exec!` to run the command at a
place where you can catch any exceptions:

```ruby
child = Progeny::Command.build('git', 'log', :max => 100)
begin
  child.exec!
rescue Progeny::MaximumOutputExceeded
  # limit was reached
end
child.out
# => "commit fa54abe139fd045bf6dc1cc259c0f4c06a9285bb\n..."
```

Please note that when the `MaximumOutputExceeded` exception is raised, the
actual combined `out` and `err` data may be a bit longer than the `:max`
value due to internal buffering.

## Why fork posix-spawn

This gem is a fork of the
[`posix-spawn`](https://github.com/rtomayko/posix-spawn) gem. Originally,
`posix-spawn` was developed as a higher-performance alternative to Ruby's
built-in `Process.spawn` method. It achieved this by utilizing the
[`posix_spawn()`](https://man7.org/linux/man-pages/man3/posix_spawn.3.html)
system call, which resulted in significant performance improvements, as
demonstrated in the benchmarks below.

However, the performance advantage of `posix-spawn` diminished with the release
of Ruby 2.2. In this version, Ruby transitioned from using the `fork()` system
call to [`vfork()`](https://man7.org/linux/man-pages/man2/vfork.2.html), which
creates a new process without copying the parent process's page tables, leading
to enhanced performance.

The following benchmarks illustrate the performance comparison:

- Performance comparison at the time of `posix-spawn` creation (Ruby used `fork` + `exec`):
![image](https://user-images.githubusercontent.com/20481048/235776984-048669d9-8949-4bf8-90e8-632984ae0516.png)

Source: [`posix-spawn` README](https://github.com/rtomayko/posix-spawn/blob/313f2abd4b9b5e737615178e0b353114481b9ab8/README.md#benchmarks)

- Current performance comparison (Ruby's built-in functionality is now more performant):
![image](https://user-images.githubusercontent.com/20481048/235777021-7e7afb19-0f73-41f1-bbc9-9bc952581c4d.png)

Source: Generated with the script in [this gist](https://gist.github.com/luanzeba/a1ebe2497ed4e2fb6491fd1780a52440) on a Debian 11 (bullseye) x86_64 machine.

For that reason, we decided to delete all of the custom spawn implementations
in the original gem: `POSIX::Spawn#spawn`, `POSIX::Spawn#popen4`,
`Kernel#system`, and <code>Kernel#\`</code>.

However, we didn't want to completely remove our use of `posix-spawn` because
we really enjoy the interface provided by `POSIX::Spawn::Child`. That's how
`progeny` came to be. It maintains all of the functionality provided by
`POSIX::Spawn::Child` under a new namespace: `Progeny::Command`.

## How to migrate from `posix-spawn` to `progeny`

1. Remove all usage of `POSIX::Spawn` as a Mixin.
Progeny does not include a Mixin so if you're including `POSIX::Spawn` in any
classes like so:
```ruby
require 'posix/spawn'

class YourSpawnerClass
  include POSIX::Spawn

  # [...]
end
```

You will need to remove the include statements and replace any use of `#spawn`
with Ruby's native `Process.spawn` and  `#popen4` with `Progeny::Command.spawn_with_pipes`
```diff
- require 'posix/spawn'

class YourSpawnerClass
- include POSIX::Spawn

  def speak(message)
-   pid = spawn('echo', message)
+   pid = Process.spawn('echo', message)
    Process::waitpid(pid)
  end

  def calculate(expression)
-   pid, in, out, err = popen4('bc')
+   pid, in, out, err = Progeny::Command.spawn_with_pipes('bc')
    in.write(expression)
    in.close
    out.read
  ensure
    [in, out, err].each { |io| io.close if !io.closed? }
    Process::waitpid(pid)
    $?
  end
end
```

2. Find and replace in Gemfile
```diff
- gem 'posix-spawn'
+ gem 'progeny'
```
3. Find and replace `POSIX::Spawn::Child` with `Progeny::Command` and any `POSIX::Spawn` exceptions with `Progeny`
```diff
class GitDiff
  def compare(from_sha, to_sha)
-   child = POSIX::Spawn::Child.new("git", "diff #{from_sha}..#{to_sha}")
+   child = Progeny::Command.new("git", "diff #{from_sha}..#{to_sha}")
    child.out
  end

  def compare_to_remote_head
-   child = POSIX::Spawn::Child.build('git', 'diff origin/main HEAD')
+   child = Progeny::Command.build('git', 'diff origin/main HEAD')
    begin
      child.exec!
-   rescue POSIX::Spawn::MaximumOutputExceeded
+   rescue Progeny::MaximumOutputExceeded
      # limit was reached
    end
    child.out
  end
end
```

4. Confirm all is working as expected
`bundle install` and make sure your tests are passing. If you encounter any
issues feel free to open an issue or a PR.

