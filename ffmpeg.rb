require_relative './util'

require 'shellwords'

module FFMPEG
   FFPROBE_PATH = File.join('/', 'usr', 'bin', 'ffprobe')
   FFMPEG_PATH = File.join('/', 'usr', 'bin', 'ffmpeg')

   # Common video extensions.
   VIDEO_EXTENSIONS = [
      '3g2', '3gp',
      'amv', 'asf', 'avi',
      'drc',
      'f4a', 'f4b', 'f4p', 'f4v', 'flv',
      'gif', 'gifv',
      'm2v', 'm4p', 'm4v', 'mkv', 'mng', 'mov', 'mp2', 'mp4', 'mpe', 'mpeg', 'mpg', 'mpv', 'mxf',
      'nsv',
      'ogg', 'ogm', 'ogv', # .ogm is also used as a audio format, but people often misuse it for ogv.
      'qt',
      'rm', 'rmvb', 'roq',
      'svi',
      'ts',
      'vob',
      'webm', 'wmv',
      'yuv'
   ]

   # Common subtitle extensions.
   SUBTITLE_EXTENSIONS = ['aqt', 'ass', 'jss', 'pjs', 'rt', 'sbv', 'smi', 'srt', 'ssa', 'stl', 'sub', 'vtt']

   # Directory names that subtitles are often held in.
   SUBTITLE_DIRS = ['sub', 'subs', 'subtitle', 'subtitles']

   # Subs we can convert to webvtt.
   # We must whitelist any subs we will use.
   CONVERTABLE_SUBTITLE_CODECS = ['ass', 'mov_text', 'srt', 'ssa', 'subrip']

   # Subs we cannot convert to webvtt.
   UNCONVERTABLE_SUBTITLE_CODECS = ['dvd_subtitle', 'hdmv_pgs_subtitle']

   KNOWN_SUBTITLE_CODECS = CONVERTABLE_SUBTITLE_CODECS + UNCONVERTABLE_SUBTITLE_CODECS

   SUBTITLE_CODECS = [
      'ass', 'dvb_subtitle', 'dvb_teletext', 'dvd_subtitle', 'eia_608',
      'hdmv_pgs_subtitle', 'hdmv_text_subtitle', 'jacosub',
      'microdvd', 'mov_text', 'mpl2', 'pjs', 'realtext',
      'sami', 'srt', 'ssa', 'stl', 'subrip', 'subviewer',
      'subviewer1', 'text', 'vplayer', 'webvtt', 'xsub'
   ]

   # Sometime images are included as a stream.
   # They look like video streams, but we want to put them in 'other' streams instead.
   IMAGE_STREAM_CODECS = ['mjpeg', 'pgm', 'png', 'ppm', 'tiff']

   def FFMPEG.formatArgs(args)
      return Shellwords.join(args)
   end

   def FFMPEG.transcode(inPath, outPath, additionalArgs)
      args = [
         '-i', inPath,  # input file
         '-y',  # Overwite output files
         '-nostats',  # Make quieter
         '-loglevel', 'warning'  # Make quieter
      ]

      args += additionalArgs
      args << outPath

      command = "#{FFMPEG_PATH} #{FFMPEG.formatArgs(args)}"

      Util.run(command)
   end

   def FFMPEG.probe(path)
      args = [
         '-hide_banner',
         '-show_streams',
         '-show_format',
         path
      ]

      command = "#{FFPROBE_PATH} #{FFMPEG.formatArgs(args)}"
      stdout, _ = Util.run(command)
      return stdout
   end

   # Pull all the subtitle streams (idexed by |subStreams|) out of the container and write
   # them to individual files.
   # If there are multiple sub streams, all streams past the first one will get suffixed with a number
   # (starting at 1).
   def FFMPEG.extractSubs(path, outDir, subStreams, codec, extension)
      subStreams.each_index{|i|
         args = [
            '-map', "0:#{subStreams[i]}",
            '-c:s', "#{codec}"
         ]

         outPath = File.join(outDir, File.basename(path).sub(/#{File.extname(path)}$/, ".#{extension}"))
         if (i != 0)
            outPath = File.join(outDir, File.basename(path).sub(/#{File.extname(path)}$/, ".#{i}.#{extension}"))
         end

         FFMPEG.transcode(path, outPath, args)
      }
   end

   def FFMPEG.getStreams(path)
      # :state_open, :state_metadata, :state_stream

      streams = {
         :metadata => {},
         :video => [],
         :audio => [],
         :subtitle => [],
         :other => []
      }

      rawInfo = FFMPEG.probe(path)

      state = :state_open
      currentStream = nil

      rawInfo.each_line{|line|
         line.strip!()

         begin
            case state
            when :state_open
               if (line == '[FORMAT]')
                  state = :state_metadata
               elsif (line == '[STREAM]')
                  state = :state_stream
                  currentStream = {}
               end
            when :state_metadata
               if (line == '[/FORMAT]')
                  state = :state_open
               else
                  data = line.downcase().sub(/^tag:/, '').split('=', 2)
                  streams[:metadata][data[0].strip()] = data[1].strip()
               end
            when :state_stream
               if (line == '[/STREAM]')
                  case currentStream['codec_type']
                  when 'video'
                     # Some attached images look like video streams.
                     if ((currentStream.has_key?('codec_name') && IMAGE_STREAM_CODECS.include?(currentStream['codec_name'])) ||
                           (currentStream.has_key?('mimetype') && currentStream['mimetype'].downcase().start_with?('image')))
                        streams[:other] << currentStream
                     else
                        streams[:video] << currentStream
                     end
                  when 'audio'
                     streams[:audio] << currentStream
                  when 'subtitle'
                     # Ensure that 'lang' is populated if 'language' exists.
                     if (currentStream.has_key?('language') && !currentStream.has_key?('lang'))
                        currentStream['lang'] = currentStream['language']
                     end

                     streams[:subtitle] << currentStream
                  when 'attachment'
                     streams[:other] << currentStream
                  else
                     puts "Unknown codec_type: #{currentStream['codec_type']}."
                     streams[:other] << currentStream
                  end

                  currentStream = nil
                  state = :state_open
               else
                  data = line.downcase().sub(/^tag:/, '').split('=', 2)
                  currentStream[data[0]] = data[1]
               end
            else
               puts "Unknown case: #{state}."
               exit 1
            end
         rescue Exception => ex
         end
      }

      return streams
   end
end
