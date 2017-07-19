require 'etc'
require 'open3'

# gem install thread
require 'thread/pool'

module Util
   DEFAULT_NUM_THREADS = [1, Etc.nprocessors - 2].max()

   def Util.debugPuts(text, debug)
      if (debug)
         puts(text)
      end
   end

   def Util.run(command, outFile=nil, errFile=nil)
      stdout, stderr, status = Open3.capture3(command)

      if (outFile != nil)
         File.open(outFile, 'w'){|file|
            file.puts(stdout)
         }
      end

      if (errFile != nil)
         File.open(errFile, 'w'){|file|
            file.puts(stderr)
         }
      end

      if (status.exitstatus() != 0)
         raise "Failed to run command: [#{command}]. Exited with status: #{status}" +
               "\n--- Stdout ---\n#{stdout}" +
               "\n--- Stderr ---\n#{stderr}"
      end

      return stdout, stderr
   end

   # |tasks| should be a bunch of procs.
   # |labels| should be 1-1 labels for |tasks|.
   # If an error occurs, it will be reported with the label as the key.
   def Util.parallel(tasks, labels, verbose = false, numThreads = Util::DEFAULT_NUM_THREADS)
      errors = {}
      pool = Thread.pool(numThreads)

      tasks.each_index{|i|
         pool.process{
            begin
               if (verbose)
                  puts "Running: #{labels[i]}"
               end

               tasks[i].call()

               if (verbose)
                  puts "Complete: #{labels[i]}"
               end
            rescue Exception => ex
               if (verbose)
                  puts "Error: #{labels[i]}"
               end

               errors[labels[i]] = ex
            end
         }
      }

      pool.wait(:done)
      pool.shutdown()

      return errors
   end
end
