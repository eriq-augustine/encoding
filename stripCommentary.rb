require_relative './ffmpeg'
require_relative './util'

require 'fileutils'
require 'tmpdir'

RAND_NAME_LENGTH = 32

def stripFile(path)
    streams = FFMPEG.getStreams(path)

    if (streams[:audio].size() == 1)
        puts "WARN: Only one audio stream. Will not strip. #{path}"
        return
    end

    commentaryStreams = []

    streams[:audio].each{|audioStream|
        if (!audioStream.has_key?('title') || !audioStream['title'].downcase().include?('commentary'))
            next
        end

        commentaryStreams << audioStream['index'].to_i()
    }

    if (commentaryStreams.size() == 0)
        puts "ERROR: Could not locate target audio stream. #{path}"
        return
    end

    streamCount = streams[:video].size() + streams[:audio].size() + streams[:subtitle].size() + streams[:other].size()

    args = [
        '-c:a', 'copy',
        '-c:v', 'copy',
        '-c:s', 'copy'
    ]

    (0...streamCount).each{|streamId|
        if (commentaryStreams.include?(streamId))
            next
        end

        args += ['-map', "0:#{streamId}"]
    }

    tempPath = File.join(Dir.tmpdir, Util.randString(RAND_NAME_LENGTH) + File.extname(path))
    FFMPEG.transcode(path, tempPath, args)
    FileUtils.mv(tempPath, path)
end

def main(targets)
    tasks = []
    labels = []

    targets.each{|target|
        tasks << Proc.new{ stripFile(target) }
        labels << target
    }

    Util.parallel(tasks, labels, true, 2)
end

def parseArgs(args)
    if (args.size() == 0 || args.map{|arg| arg.gsub('-', '').downcase()}.include?('help'))
        puts "USAGE: ruby #{$0} <file> ..."
        puts "Strip commentary audio streams from a file."
        exit(1)
    end

    return args
end

if (__FILE__ == $0)
    main(parseArgs(ARGV))
end
