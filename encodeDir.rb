require_relative './ffmpeg'
require_relative './vp9'

require 'fileutils'

DIRENT_TYPE_DIR = 'dir'
DIRENT_TYPE_FILE = 'file'

# Recursivley parse a dir and get info about the contents.
# Return: {
#     :type => DIRENT_TYPE_DIR,
#     :name => dirname,
#     :path => absPath,
#     :contents = [ { ... }, ...]
# }
def parseDir(path, relativePath)
   if (!File.directory?(path))
      raise("Told to parse a path that is not a dir: #{path}")
   end

   relativePath = File.join(relativePath, File.basename(path))

   contents = []
   dirsToExplore = []

   Dir.foreach(path){|dirent|
      if (dirent == '.' || dirent == '..')
         next
      end

      direntPath = File.join(path, dirent)

      if (File.directory?(direntPath))
         dirsToExplore << direntPath
      else
         contents << {
            :type => DIRENT_TYPE_FILE,
            :name => File.basename(direntPath),
            :path => File.absolute_path(direntPath),
            :relPath => File.join(relativePath, dirent),
            :ext => File.extname(direntPath).sub(/^\./, '').downcase()
         }
      end
   }

   dirsToExplore.each{|dirPath|
      contents << parseDir(dirPath, relativePath)
   }

   return {
      :type => DIRENT_TYPE_DIR,
      :name => File.basename(path),
      :path => File.absolute_path(path),
      :relPath => relativePath,
      :contents => contents
   }
end

# Figure out the work that needs to be done.
# Returns: [[directories to make], [files to copy], [files to encode]]
def splitWork(dirInfo)
   dirs = [dirInfo[:relPath]]
   toCopy = []
   toEncode = []

   dirInfo[:contents].each{|dirent|
      if (dirent[:type] == DIRENT_TYPE_DIR)
         tempDirs, tempToCopy, tempToEncode = splitWork(dirent)

         dirs += tempDirs
         toCopy += tempToCopy
         toEncode += tempToEncode
      else
         if (dirent[:ext] != 'webm' && FFMPEG::VIDEO_EXTENSIONS.include?(dirent[:ext]))
            toEncode << dirent
         else
            toCopy << dirent
         end
      end
   }

   return dirs, toCopy, toEncode
end

def makeDirs(outputDir, dirs)
   dirs.each{|dir|
      FileUtils.mkdir_p(File.join(outputDir, dir))
   }
end

def copy(outputDir, files)
   files.each{|file|
      FileUtils.cp(file[:path], File.join(outputDir, file[:relPath]))
   }
end

# Get the streams for each video file and throw on any ones that are hard to encode.
def getStreams(files)
   violations = Hash.new{|hash, key| hash[key] = []}

   files.each{|file|
      file[:streams] = FFMPEG.getStreams(file[:path])

      if (file[:streams][:video].size() == 0)
         violations['no video streams'] << file
      end

      if (file[:streams][:audio].size() == 0)
         violations['no audio streams'] << file
      end

      if (file[:streams][:video].size() > 1)
         violations['multiple video streams'] << file
      end

      if (file[:streams][:audio].size() > 1)
         violations['multiple audio streams'] << file
      end

      if (file[:streams][:subtitle].size() > 0)
         violations['has subtitles'] << file
      end
   }

   if (violations.size() > 0)
      reasons = violations.to_a().map{|reason, files| "{#{reason}: [#{files.map{|file| file[:path]}.join(', ')}]}"}
      raise("Found files we cannot encode -- #{reasons}")
   end
end

def encodeFiles(outputDir, files)
   tasks = []
   labels = []

   files.each{|file|
      outPath = File.join(outputDir, file[:relPath].sub(/#{File.extname(file[:relPath])}$/, '.webm'))

      tasks << Proc.new{ VP9.transcode(file[:path], outPath) }
      labels << file[:path]
   }

   Util.parallel(tasks, labels, true)
end

def main(targetDir, outputDir)
   dirInfo = parseDir(targetDir, '.')

   dirs, toCopy, toEncode = splitWork(dirInfo)

   # Before doing any file operations, make sure any encode files look clean.
   getStreams(toEncode)

   makeDirs(outputDir, dirs)
   copy(outputDir, toCopy)
   encodeFiles(outputDir, toEncode)
end

def parseArgs(args)
   if (args.size != 2 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <target dir> <output dir>"
      puts "Make a copy of <target dir> inside of <output dir> with all video files transcoded as webm."
      puts "All non-video files will be directly copied over."
      puts "If there is any reason the directory cannot be easily encoded, we will panic before any"
      puts "encoding or copying is done."
      exit(1)
   end

   targetDir = args.shift()
   outputDir = args.shift()

   return targetDir, outputDir
end

if (__FILE__ == $0)
   main(*parseArgs(ARGV))
end
