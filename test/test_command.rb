# frozen_string_literal: true

require 'test_helper'

class CommandTest < Minitest::Test
  # Become a new process group.
  def setup
    Process.setpgrp
  end

  # Kill any orphaned processes in our process group before continuing but
  # ignore the TERM signal we receive.
  def teardown
    trap("TERM") { trap("TERM", "DEFAULT") }
    begin
      Process.kill("-TERM", Process.pid)
      Process.wait
    rescue Errno::ECHILD
    end
  end

  # verify the process is no longer running and has been reaped.
  def assert_process_reaped(pid)
    Process.kill(0, pid)
    assert false, "Process #{pid} still running"
  rescue Errno::ESRCH
  end

  # verifies that all processes in the given process group are no longer running
  # and have been reaped. The current ruby test process is excluded.
  # XXX It's weird to use the SUT here but the :pgroup option is useful. Could
  # be a IO.popen under Ruby >= 1.9 since it also supports :pgroup.
  def assert_process_group_reaped(pgid)
    command = "ps axo pgid,pid,args | grep '^#{pgid} ' | grep -v '^#{pgid} #$$'"
    procs = Progeny::Command.new(command, :pgroup => true).out
    assert procs.empty?, "Processes in group #{pgid} still running:\n#{procs}"
  end

  def test_argv_array_execs
    p = Progeny::Command.new('printf', '%s %s %s', '1', '2', '3 4')
    assert p.success?
    assert_equal "1 2 3 4", p.out
  end

  def test_argv_string_uses_sh
    p = Progeny::Command.new("echo via /bin/sh")
    assert p.success?
    assert_equal "via /bin/sh\n", p.out
  end

  def test_stdout
    p = Progeny::Command.new('echo', 'boom')
    assert_equal "boom\n", p.out
    assert_equal "", p.err
  end

  def test_stderr
    p = Progeny::Command.new('echo boom 1>&2')
    assert_equal "", p.out
    assert_equal "boom\n", p.err
  end

  def test_status
    p = Progeny::Command.new('exit 3')
    assert !p.status.success?
    assert_equal 3, p.status.exitstatus
  end

  def test_env
    p = Progeny::Command.new({ 'FOO' => 'BOOYAH' }, 'echo $FOO')
    assert_equal "BOOYAH\n", p.out
  end

  def test_chdir
    p = Progeny::Command.new("pwd", :chdir => File.dirname(Dir.pwd))
    assert_equal File.dirname(Dir.pwd) + "\n", p.out
  end

  def test_input
    input = "HEY NOW\n" * 100_000 # 800K
    p = Progeny::Command.new('wc', '-l', :input => input)
    assert_equal 100_000, p.out.strip.to_i
  end

  def test_max
    child = Progeny::Command.build('yes', :max => 100_000)
    assert_raises(Progeny::MaximumOutputExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped Process.pid
  end

  def test_max_pgroup_kill
    child = Progeny::Command.build('yes', :max => 100_000, :pgroup_kill => true)
    assert_raises(Progeny::MaximumOutputExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped child.pid
  end

  def test_max_with_child_hierarchy
    child = Progeny::Command.build('/bin/sh', '-c', 'true && yes', :max => 100_000)
    assert_raises(Progeny::MaximumOutputExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped Process.pid
  end

  def test_max_with_child_hierarchy_pgroup_kill
    child = Progeny::Command.build('/bin/sh', '-c', 'true && yes', :max => 100_000, :pgroup_kill => true)
    assert_raises(Progeny::MaximumOutputExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped child.pid
  end

  def test_max_with_stubborn_child
    child = Progeny::Command.build("trap '' TERM; yes", :max => 100_000)
    assert_raises(Progeny::MaximumOutputExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped Process.pid
  end

  def test_max_with_stubborn_child_pgroup_kill
    child = Progeny::Command.build("trap '' TERM; yes", :max => 100_000, :pgroup_kill => true)
    assert_raises(Progeny::MaximumOutputExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped child.pid
  end

  def test_max_with_partial_output
    p = Progeny::Command.build('yes', :max => 100_000)
    assert_nil p.out
    assert_raises Progeny::MaximumOutputExceeded do
      p.exec!
    end
    assert_output_exceeds_repeated_string("y\n", 100_000, p.out)
    assert_process_reaped p.pid
    assert_process_group_reaped Process.pid
  end

  def test_max_with_partial_output_long_lines
    p = Progeny::Command.build('yes', "nice to meet you", :max => 10_000)
    assert_raises Progeny::MaximumOutputExceeded do
      p.exec!
    end
    assert_output_exceeds_repeated_string("nice to meet you\n", 10_000, p.out)
    assert_process_reaped p.pid
    assert_process_group_reaped Process.pid
  end

  def test_timeout
    start = Time.now
    child = Progeny::Command.build('sleep', '1', :timeout => 0.05)
    assert_raises(Progeny::TimeoutExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped Process.pid
    assert (Time.now-start) <= 0.2
  end

  def test_timeout_pgroup_kill
    start = Time.now
    child = Progeny::Command.build('sleep', '1', :timeout => 0.05, :pgroup_kill => true)
    assert_raises(Progeny::TimeoutExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped child.pid
    assert (Time.now-start) <= 0.2
  end

  def test_timeout_with_child_hierarchy
    child = Progeny::Command.build('/bin/sh', '-c', 'true && sleep 1', :timeout => 0.05)
    assert_raises(Progeny::TimeoutExceeded) { child.exec! }
    assert_process_reaped child.pid
  end

  def test_timeout_with_child_hierarchy_pgroup_kill
    child = Progeny::Command.build('/bin/sh', '-c', 'true && sleep 1', :timeout => 0.05, :pgroup_kill => true)
    assert_raises(Progeny::TimeoutExceeded) { child.exec! }
    assert_process_reaped child.pid
    assert_process_group_reaped child.pid
  end

  def test_timeout_with_partial_output
    start = Time.now
    p = Progeny::Command.build('echo Hello; sleep 1', :timeout => 0.05, :pgroup_kill => true)
    assert_raises(Progeny::TimeoutExceeded) { p.exec! }
    assert_process_reaped p.pid
    assert_process_group_reaped Process.pid
    assert (Time.now-start) <= 0.2
    assert_equal "Hello\n", p.out
  end

  def test_lots_of_input_and_lots_of_output_at_the_same_time
    input = "stuff on stdin \n" * 1_000
    command = "
      while read line
      do
        echo stuff on stdout;
        echo stuff on stderr 1>&2;
      done
    "
    p = Progeny::Command.new(command, :input => input)
    assert_equal input.size, p.out.size
    assert_equal input.size, p.err.size
    assert p.success?
  end

  def test_input_cannot_be_written_due_to_broken_pipe
    input = "1" * 100_000
    p = Progeny::Command.new('false', :input => input)
    assert !p.success?
  end

  def test_utf8_input
    input = "hålø"
    p = Progeny::Command.new('cat', :input => input)
    assert p.success?
  end

  def test_utf8_input_long
    input = "hålø" * 10_000
    p = Progeny::Command.new('cat', :input => input)
    assert p.success?
  end

  def test_spawn_with_pipes
    pid, i, o, e = Progeny::Command.spawn_with_pipes("cat")
    i.write "hello world"
    i.close
    Process.waitpid(pid)
    assert_equal "hello world", o.read
    assert_equal 0, $?.exitstatus
  ensure
    [i, o, e].each{ |io| io.close rescue nil }
  end

  def test_spawn_with_pipes_and_options
    pid, i, o, e = Progeny::Command.spawn_with_pipes("cat", pgroup: true)
    i.write "hello world"
    assert_equal pid, Process.getpgid(pid)
    i.close
    Process.waitpid(pid)
    assert_equal "hello world", o.read
    assert_equal 0, $?.exitstatus
  ensure
    [i, o, e].each{ |io| io.close rescue nil }
  end

  ##
  # Assertion Helpers

  def assert_output_exceeds_repeated_string(str, len, actual)
    assert_operator actual.length, :>=, len

    expected = (str * (len / str.length + 1)).slice(0, len)
    assert_equal expected, actual.slice(0, len)
  end
end
