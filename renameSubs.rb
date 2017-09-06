# We will perform an in-order depth-first traversal of some directory.
# Instead of traversing first and collecting tasks, we will forgo the long spinup
# and just go single threaded.

# We will search for any webm files for adjacent subtitiles that are formatted inforrectly.
# Sub sets with correct and incorrect formats will be reported.
# We are only anticipating adjacent vtt subtitles.
# We will do simple language detection and correct the subtitiles name.
# Format is: "#{base file name}.#{iso2 language or 'un' for unknown'}#{'.' and a number if there is more than 1 sub}.vtt"

# gem install whatlanguage
require 'whatlanguage'

require 'fileutils'

UNKNOWN_LANG = 'un'

$languageDetector = WhatLanguage.new(:all)

# Read a sub file and clean up the text so the language can be inferred.
def getCleanText(path)
   lines = []

   File.open(path, 'r'){|file|
      file.each{|line|
         line = line.strip()

         # Skip empty and header lines.
         if (line == '' || line == 'WEBVTT')
            next
         end

         # Skip timing lines.
         if (line.match(/\d+:\d\+.\d+ --> \d+:\d\+.\d+/))
            next
         end

         lines << line
      }
   }

   return lines.join("\n")
end

# Returns UNKNOWN_LANG if it can't figure it out.
def detectLang(path)
   # The language detector is not doing well for subs, so we will just always assume english...
   return 'en'

   lang = $languageDetector.language_iso(getCleanText(path))
   if (lang != nil)
      return lang.to_s()
   end

   return UNKNOWN_LANG
end

def parseDir(path, dry)
   if (!File.directory?(path))
      raise("Told to parse a path that is not a dir: #{path}")
   end

   videoFiles = []
   subFiles = []

   dirsToExplore = []

   Dir.foreach(path).to_a().sort().each{|dirent|
      if (dirent == '.' || dirent == '..')
         next
      end

      direntPath = File.join(path, dirent)
      if (File.directory?(direntPath))
         dirsToExplore << direntPath
      else
         if (File.extname(dirent) == '.webm')
            videoFiles << dirent
         elsif (File.extname(dirent) == '.vtt')
            subFiles << dirent
         end
      end
   }

   # Look for adjacent subs

   # {videoPath => [sub path, ...]}
   subMap = Hash.new{|hash, key| hash[key] = []}

   # Technicailly this could capture files that are not actually associated with the target.
   # But that would mean it was originally named REALLY poorly.
   videoFiles.each{|videoFile|
      basename = File.basename(videoFile, '.*')

      subFiles.each{|subFile|
         if (subFile.start_with?(basename))
            subMap[videoFile] << subFile
            next
         end
      }
   }

   offendingFiles = []

   # {videoFile => {iso2 => [sub file, ...], ...}, ...}
   langMap = {}

   subMap.each{|videoFile, subPaths|
      videoBasename = File.basename(videoFile, '.*')

      # {iso2 => [files], ...}
      videoLangMap = Hash.new{|hash, key| hash[key] = []}

      subPaths.each{|subPath|
         # basename - vidoeBasename - '.vtt'
         additionalInfo = File.basename(subPath, '.vtt').sub(videoBasename, '').strip()

         # We will be giving out new ids, so just ignore any old ones.
         additionalInfo = additionalInfo.sub(/[\._]\d+/, '').strip().downcase()

         additionalInfo = additionalInfo.sub(/^[\._]/, '')

         if (['eng', 'en'].include?(additionalInfo))
            videoLangMap['en'] << subPath
            next
         else
            videoLangMap[detectLang(File.join(path, subPath))] << subPath
         end

         if (additionalInfo != '')
            offendingFiles << [subPath, additionalInfo]
         end
      }

      langMap[videoFile] = videoLangMap
   }

   # Instead of trying to deal with random additional information,
   # just throw up our hands and make the user deal with it.
   if (offendingFiles.size() > 0)
      puts "Found some sub files with unknown additional information:"
      offendingFiles.each{|offendingFile, additionalInfo|
         puts "   '#{File.join(path, offendingFile)}' => '#{additionalInfo}'"
      }

      exit(1)
   end

   langMap.each{|videoFile, videoLangMap|
      videoBasename = File.basename(videoFile, '.*')

      videoLangMap.each{|lang, subFiles|
         subFiles.each_with_index{|subFile, i|
            subPath = File.join(path, subFile)

            newName = "#{videoBasename}.#{lang}.#{i}.vtt"
            if (subFiles.size() == 1)
               newName = "#{videoBasename}.#{lang}.vtt"
            end
            
            newPath = File.join(path, newName)

            if (subPath == newPath)
               next
            end

            puts "mv '#{subPath}' '#{newPath}'"
            if (!dry)
               FileUtils.mv(subPath, newPath)
            end
         }
      }
   }

   # Descend into all the child dirs.
   dirsToExplore.each{|dir|
      parseDir(dir, dry)
   }
end

def main(targetDir, dry)
   parseDir(targetDir, dry)
end

def parseArgs(args)
   if (![1, 2].include?(args.size()) || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
      puts "USAGE: ruby #{$0} <target dir> --dry"
      puts "   Search for any webm files for adjacent subtitiles that are formatted inforrectly."
      puts "   Sub sets with correct and incorrect formats will be reported."
      puts "   We are only anticipating adjacent vtt subtitles."
      puts "   We will do simple language detection and correct the subtitiles name."
      puts "   Format is: \#{base file name}.\#{language}.\#{identifier}.vtt"
      puts "   The language will wither be an ISO2 code or 'un' for unknown."
      puts "   The identifier is optional and will only be used if there are multiple subs with the same language for a single file."
      puts ""
      puts "   On a dry run, we will only output the renames that will be made."
      exit(1)
   end

   targetDir = args.shift()

   dry = false
   if (args.size() > 0)
      arg = args.shift()

      if (arg != '--dry')
         puts "Unknown arg: [#{arg}]"
         exit(2)
      end

      dry = true
   end

   return targetDir, dry
end

if (__FILE__ == $0)
   main(*parseArgs(ARGV))
end
