require_relative './util'

require 'fileutils'
require 'shellwords'
require 'tmpdir'

DEBUG = true

RAND_NAME_LENGTH = 32

SUPPORTED_IMAGE_EXTENSIONS = ['jpg', 'png', 'gif']
SUPPORTED_ARCHIVE_EXTENSIONS = ['rar', 'tar', 'zip']

# These files will be removed if they are seen.
REMOVE_FILES = ['Thumbs.db', '.DS_Store']

MOZCJPEG_PATH = File.join('/', 'home', 'eriq', 'bin', 'mozcjpeg')
PNGQUANT_PATH = File.join('/', 'usr', 'bin', 'pngquant')

RAR_PATH = File.join('/', 'usr', 'bin', 'rar')
TAR_PATH = File.join('/', 'usr', 'bin', 'tar')
UNZIP_PATH = File.join('/', 'usr', 'bin', 'unzip')

def tar(workDir, targetDir, targetTarPath)
   args = [
      TAR_PATH,
      'cf', targetTarPath,
      '--directory', workDir,
      targetDir
   ]

   Util.run(Shellwords.join(args))
end

def collectImages(path, seenDirs = 0)
   images = []

   Dir.foreach(path).to_a().sort().each{|dirent|
      if (dirent == '.' || dirent == '..')
         next
      end

      direntPath = File.join(path, dirent)
      info = {
         :name => dirent,
         :path => direntPath,
         :outputPath => nil,
         :ext => File.extname(dirent).sub(/^\./, '')
      }

      if (File.directory?(direntPath))
         # We will only tolerate a single directory in the archive.
         if (seenDirs > 0)
            raise("Seen multiple dirs!: [#{direntPath}]")
         end
         seenDirs += 1

         images += collectImages(direntPath, seenDirs)
      elsif (SUPPORTED_IMAGE_EXTENSIONS.include?(info[:ext]))
         images << info
      elsif (REMOVE_FILES.include?(info[:name]))
         # Ignore this file and we will not copy it over.
      else
         raise("Found a non-image file in an archive: [#{direntPath}]")
      end
   }

   return images
end

def unarchive(inPath, outDir)
   ext = File.extname(inPath).sub(/^\./, '')
   args = nil

   if (ext == 'rar')
      args = [
         RAR_PATH,
         'x', inPath,
         outDir
      ]
   elsif (ext == 'tar')
      args = [
         TAR_PATH,
         'xf', inPath,
         '--directory', outDir
      ]
   elsif (ext == 'zip')
      args = [
         UNZIP_PATH,
         inPath,
         '-d', outDir
      ]
   else
      raise("Can't handle this archive type: [#{inPath}]")
   end

   Util.run(Shellwords.join(args))
end

def optimizeJPG(inPath, outPath)
   args = [
      MOZCJPEG_PATH,
      '-quality', '85',
      '-outfile', outPath,
      inPath
   ]

   Util.run(Shellwords.join(args))
end

def optimizePNG(inPath, outPath)
   args = [
      PNGQUANT_PATH,
      '--speed', '1',
      '--strip',
      '--force',
      '--output', outPath,
      inPath
   ]

   Util.run(Shellwords.join(args))
end

def optimizeImage(inPath, outPath)
   ext = File.extname(inPath).sub(/^\./, '')

   if (ext == 'jpg')
      optimizeJPG(inPath, outPath)
   elsif (ext == 'png')
      optimizePNG(inPath, outPath)
   elsif (ext == 'gif')
      FileUtils.cp(inPath, outPath)
   else
      raise("Can't handle this image type: [#{inPath}]")
   end
end

# Just copy other files.
def handleOtherFile(fileInfo)
   if (File.exist?(fileInfo[:outputPath]))
      puts "SKIPPING: Copy target already exists: #{fileInfo[:outputPath]}"
      return
   end

   # "Remove" (just don't copy) some files.
   if (REMOVE_FILES.include?(fileInfo[:path]))
      return
   end

   FileUtils.cp(fileInfo[:path], fileInfo[:outputPath])
end

def handleSingleImage(fileInfo)
   if (File.exist?(fileInfo[:outputPath]))
      puts "SKIPPING: Single optimize target already exists: #{fileInfo[:outputPath]}"
      return
   end

   optimizeImage(fileInfo[:path], fileInfo[:outputPath])
end

# Handle several image files in parallel.
def handleSingleImages(files)
   tasks = []
   labels = []

   files.each{|fileInfo|
      tasks << Proc.new{ handleSingleImage(fileInfo) }
      labels << fileInfo[:path]
   }

   Util.parallel(tasks, labels, DEBUG)
end

def handleArchive(fileInfo)
   finalPath = fileInfo[:outputPath].sub(/#{fileInfo[:ext]}$/, 'tar')

   if (File.exist?(finalPath))
      puts "SKIPPING: Archive target already exists: #{finalPath}"
      return
   end

   tempPath = File.join(Dir.tmpdir, "image_optimize_#{Util.randString(RAND_NAME_LENGTH)}")
   FileUtils.mkdir_p(tempPath)

   begin
      # Unarchive into the temp dir.
      rawArchiveDir = File.join(tempPath, 'raw')
      FileUtils.mkdir_p(rawArchiveDir)
      unarchive(fileInfo[:path], rawArchiveDir)

      # Make sure we see only images.
      # We also only expect at most one level of dirs.
      images = collectImages(rawArchiveDir)

      # Correct the output path for these images.
      finalDirName = File.basename(fileInfo[:name], '.*')
      optimialDir = File.join(tempPath, 'optimal')
      optimizedArchiveDir = File.join(optimialDir, finalDirName)
      FileUtils.mkdir_p(optimizedArchiveDir)

      images.each{|image|
         image[:outputPath] = File.join(optimizedArchiveDir, image[:name])
      }

      # Optimize all the images into the temp target (with the same basename name as the archive).
      handleSingleImages(images)

      # Tar up the dir.
      tempTarPath = File.join(optimialDir, 'temp.tar')
      tar(optimialDir, finalDirName, tempTarPath)

      # Move it to the final location.
      FileUtils.mv(tempTarPath, finalPath)
   rescue Exception => ex
      puts "ERROR: Failed to handle archive: #{fileInfo[:path]}"
      puts ex
   end

   FileUtils.rm_r(tempPath)
end

def parseDir(path, outputPath)
   if (!File.directory?(path))
      raise("Told to parse a path that is not a dir: #{path}")
   end

   outputPath = File.join(outputPath, File.basename(path))

   imageFiles = []
   archiveFiles = []
   otherFiles = []

   dirsToExplore = []

   Dir.foreach(path).to_a().sort().each{|dirent|
      if (dirent == '.' || dirent == '..')
         next
      end

      direntPath = File.join(path, dirent)
      info = {
         :name => dirent,
         :path => direntPath,
         :outputPath => File.join(outputPath, dirent),
         :ext => File.extname(dirent).sub(/^\./, '')
      }

      if (File.directory?(direntPath))
         dirsToExplore << direntPath
      elsif (SUPPORTED_IMAGE_EXTENSIONS.include?(info[:ext]))
         imageFiles << info
      elsif (SUPPORTED_ARCHIVE_EXTENSIONS.include?(info[:ext]))
         archiveFiles << info
      else
         otherFiles << info
      end
   }

   FileUtils.mkdir_p(outputPath)

   otherFiles.each{|fileInfo|
      handleOtherFile(fileInfo)
   }

   handleSingleImages(imageFiles)

   archiveFiles.each{|fileInfo|
      handleArchive(fileInfo)
   }

   # Descend into all the child dirs.
   dirsToExplore.each{|dir|
      parseDir(dir, outputPath)
   }
end

def main(targetDir, outputDir)
   if (!File.file?(MOZCJPEG_PATH))
      raise("Cannot find mozjpg: [#{MOZCJPEG_PATH}].")
   end

   if (!File.file?(PNGQUANT_PATH))
      raise("Cannot find pngquant: [#{PNGQUANT_PATH}].")
   end

   parseDir(targetDir, outputDir)
end

def parseArgs(args)
   if (args.size() != 2 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <target dir> <output dir>"
      puts "Make a copy of <target dir> inside of <output dir> with all archives converted into tar and"
      puts "all images optimized."
      puts "All files that are not images or archives will be directly copied over."
      puts "We expect all archives to only have images in them and will panic on error."
      puts "If no output directory is supplied, then a dry run will be performed where no files are copied or encoded."
      exit(1)
   end

   targetDir = args.shift()
   outputDir = args.shift()

   return targetDir, outputDir
end

if (__FILE__ == $0)
   main(*parseArgs(ARGV))
end
