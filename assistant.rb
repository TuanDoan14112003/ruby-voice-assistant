require 'pocketsphinx-ruby'
require "google/cloud/speech"
require 'generator'
class Microphone
	def initialize
		@queue_buffer = Queue.new
		@closed = false
		@microphone = Pocketsphinx::Microphone.new
	end

	def start_recording
		@microphone.record do 
			buffer_ptr = FFI::MemoryPointer.new(:int16, 5000)
			while true
				sample_count = @microphone.read_audio(buffer_ptr, 5000)
				@queue_buffer.push(buffer_ptr.get_bytes(0, sample_count * 2))
			end
		end
	end
	def stop_recording
		@microphone.stop_recording
	end

	def stream
		Enumerator.new do |enum|
			
			while not @closed
				
				chunk = @queue_buffer.pop()
				if chunk == nil
					return
				end
				data = [chunk]
				while true 
					begin
						chunk = @queue_buffer.pop(non_block: true)
						if chunk == nil
							return
						end
						data.append(chunk)
					rescue
						break
					end
				end
				
				enum.yield data.join("")
		
			end
			
		end
	end
end

def print_responses(responses)
	num_chars_printed = 0
    for response in responses
        if response.results.length == 0
            next
		end
        # The `results` list is consecutive. For streaming, we only care about
        # the first result being considered, since once it's `is_final`, it
        # moves on to considering the next utterance.
        result = response.results[0]
        if result.alternatives.length == 0
            next
		end
        # Display the transcription of the top alternative.
        transcript = result.alternatives[0].transcript

        # Display interim results, but with a carriage return at the end of the
        # line, so subsequent lines will overwrite them.
        #
        # If the previous result was longer than this one, we need to print
        # some extra spaces to overwrite the previous result
		if num_chars_printed - transcript.length < 0
			overwrite_chars = ""
		else
			overwrite_chars = " " * (num_chars_printed - transcript.length)
		end

        if result.is_final == false
            STDOUT.write(transcript + overwrite_chars + "\r")
            STDOUT.flush()

            num_chars_printed = transcript.length

        else
            puts(transcript + overwrite_chars)

            # Exit recognition if any of the transcribed phrases could be
            # one of our keywords.
            # if re.search(r"\b(exit|quit)\b", transcript, re.I):
            #     print("Exiting..")
            #     break
			# end

            num_chars_printed = 0
		end
	end

end

def main()

	client =  Google::Cloud::Speech.speech
	config = Google::Cloud::Speech::V1::RecognitionConfig.new(
		encoding:                 :LINEAR16,
		sample_rate_hertz:        16_000,
		language_code:            "en-US",
		enable_word_time_offsets: true
	)
	streaming_config = Google::Cloud::Speech::V1::StreamingRecognitionConfig.new(
		config: config,
		interim_results:true

	)
	file = File.open("test.raw", "wb")
	microphone = Microphone.new
	t1 = Thread.new{microphone.start_recording()}
	stream = microphone.stream()
	
	requests = Enumerator.new do |gen|
		gen.yield Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(streaming_config:streaming_config)
		for item in stream
			gen.yield Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(audio_content: item)
		end
	end


	responses = client.streaming_recognize(requests)



	print_responses(responses)

	t1.join
end


main()



