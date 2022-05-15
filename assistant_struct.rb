require 'pocketsphinx-ruby'
require "google/cloud/speech"
require "google/cloud/text_to_speech"
require 'gosu'
require 'http'
require 'launchy'
require 'uri'

def set_up_speech_to_text(encoding , sample_rate_hertz , language_code , enable_word_time_offsets , enable_automatic_punctuation)
    speech_to_text_client =  Google::Cloud::Speech.speech
	config = Google::Cloud::Speech::V1::RecognitionConfig.new(
		encoding:                 encoding,
		sample_rate_hertz:        sample_rate_hertz,
		language_code:            language_code,
		enable_word_time_offsets: enable_word_time_offsets,
		enable_automatic_punctuation: enable_automatic_punctuation,
	)
	speech_to_text_config = Google::Cloud::Speech::V1::StreamingRecognitionConfig.new(
		config: config,
		interim_results:true
	)
    return speech_to_text_client,speech_to_text_config
end

def set_up_text_to_speech(language_code,voice_name,encoding)
    text_to_speech_client = Google::Cloud::TextToSpeech.text_to_speech()
    
	text_to_speech_voice = Google::Cloud::TextToSpeech::V1::VoiceSelectionParams.new(
		language_code: language_code, 
		name: voice_name,
	)
	text_to_speech_config = Google::Cloud::TextToSpeech::V1::AudioConfig.new(
		audio_encoding: encoding
	)
    return text_to_speech_client,text_to_speech_voice, text_to_speech_config
end

def microphone_start_recording(microphone,queue_buffer)
    Thread.new {
    microphone.record do 
        buffer_ptr = FFI::MemoryPointer.new(:int16, 5000)
        while true
            sample_count = microphone.read_audio(buffer_ptr, 5000)
            queue_buffer.push(buffer_ptr.get_bytes(0, sample_count * 2))
        end
    end 
    }
end

def microphone_stop_recording(microphone,queue_buffer)
    microphone.stop_recording
    
end

def microphone_stream(microphone, queue_buffer)
    Enumerator.new do |enum|
        while true
            chunk = queue_buffer.pop()
            if chunk == nil
                return
            end
            data = [chunk]
            while true 
                begin
                    chunk = queue_buffer.pop(non_block: true)
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

def generate_request(streaming_config,stream)
    Enumerator.new do |gen|
		gen.yield Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(streaming_config:streaming_config)
		for item in stream
			gen.yield Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(audio_content: item)
		end
	end
end

def convert_text_to_speech(response,text_to_speech_settings)
    text_to_speech_client,text_to_speech_voice,text_to_speech_config = text_to_speech_settings
    synthesis_input = Google::Cloud::TextToSpeech::V1::SynthesisInput.new(text: response)
	response = text_to_speech_client.synthesize_speech(input:synthesis_input, voice:text_to_speech_voice, audio_config:text_to_speech_config)

	file = File.new("response.wav","wb")
	file.write response.audio_content
	file.close

	puts "done"
	
end

def get_current_time(text_to_speech_settings)
    time = Time.now()
    response = time.strftime("It's %I:%M%p")  
    convert_text_to_speech(response,text_to_speech_settings)
end

def get_current_date(text_to_speech_settings)
    time = Time.now()
    response = time.strftime("Today is %A %B %d, %Y")  
    convert_text_to_speech(response,text_to_speech_settings)
end

def get_current_weather(text_to_speech_settings)
    open_weather_api_key = '31d640b8fa6ce0439aa5e350c5ca6ee0'
    open_weather_uri = "https://api.openweathermap.org/data/2.5/weather?q=Melbourne&units=metric&appid=#{open_weather_api_key}"
    response = HTTP.get(open_weather_uri)
    if response.status.code == 200
        weather = response.parse
        weather_description = weather['weather'][0]['description']
        temp = weather['main']["temp"]
        feels_like_temp = weather['main']["feels_like"]
        humidity = weather["main"]["humidity"]
        wind_speed = weather["wind"]["speed"]
        cloudiness = weather["clouds"]["all"]
        response = "It's currently #{weather_description}. Temperature is #{temp} degrees Celsius, feels like #{feels_like_temp}. Humidity is #{humidity}%. Wind speed is #{wind_speed} meters per second and #{cloudiness}% clouds"
        convert_text_to_speech(response,text_to_speech_settings)
    else 
        puts("Bad request: #{response.status.code}")
    end
end

def get_shopping_list(text_to_speech_settings)
    shopping_list_file = File.new('shopping_list.txt','r')
    shopping_list = Array.new()
    shopping_list_file.each do |item|
        shopping_list << item.chop
    end
    shopping_list_file.close()
    response = "Your shopping list is: "
    for index in 0..shopping_list.length-1
        response += shopping_list[index]
        if index == shopping_list.length-1
            response += '.'
        else
            response += ', '
        end
    end
    convert_text_to_speech(response,text_to_speech_settings)

end

def add_item_to_shopping_list(item, text_to_speech_settings)
    shopping_list = File.new("shopping_list.txt",'a+')
    item_already_existed = false
    shopping_list.each_line do |line|
        if (line.chop == item)
            item_already_existed = true
        end
    end
    if item_already_existed
        response = "The item has already in your shopping list"
    else
        shopping_list.puts item
        response = "I have added #{item} to your shopping list"
    end
    shopping_list.close()
    convert_text_to_speech(response,text_to_speech_settings)
end

def search(search_key_word,text_to_speech_settings)
    search_query = URI.encode_www_form([['q',search_key_word]])
    uri = "https://google.com/search?" + search_query
    Launchy.open(uri)
    serpapi_key="6383e617670c68b60eaf5825a8142efd2a0fb91e2abd4e4723b1f3e21944a385"
    uri = "https://serpapi.com/search?api_key=#{serpapi_key}&gl=au&#{search_query}"
    serpapi_response = HTTP.get(uri)
    response_body = serpapi_response.parse
    if response_body["answer_box"] != nil
        answer_box = response_body["answer_box"]
        if answer_box["type"] == "calculator_result"
            response = "The result is: " + response_body["answer_box"]["result"]
            puts response
        elsif answer_box["type"] == "finance_results"
            company = answer_box["title"]
            stock_price = answer_box["price"].to_s + " " + answer_box["currency"]
            response = "#{company}'s stock is #{stock_price}."
            puts response
        elsif answer_box["type"] == "population_result"
            place = answer_box["place"]
            population = answer_box["population"]
            response = "The population of #{place} is #{population}"
            puts response
        elsif answer_box["type"] == "currency_converter"
            original_price = answer_box["currency_converter"]["from"]
            converted_price = answer_box["currency_converter"]["to"]
            response = original_price["price"].to_s + " #{original_price["currency"]} is " + converted_price["price"].to_s + " #{converted_price["currency"]}."
            puts response
        elsif answer_box["type"] == "dictionary_results"
            word_type = answer_box["word_type"]
            definition_list= answer_box["definitions"]
            response = "#{answer_box["syllables"]} is a #{word_type}. It has #{definition_list.length} meanings. "
            for i in 1..definition_list.length
                response += "\n"
                response += "#{i}. #{definition_list[i-1]}"
                
            end
            puts response
        elsif answer_box["type"] == "organic_result"
            puts "vao day"
            answer_box_source = URI.parse(answer_box["link"]).host
            response = "I found a result from #{answer_box_source}: "
            answer_box_snippet = "'#{answer_box["snippet"]}'"
            response += answer_box_snippet
         
        end
    elsif response_body["knowledge_graph"] != nil
        knowledge_graph_source = response_body["knowledge_graph"]["source"]["name"]
        response = "I found a result from #{knowledge_graph_source}: "
        knowledge_graph_description = "'#{response_body["knowledge_graph"]["description"]}'"
        response += knowledge_graph_description
        puts response
    else 
        response = "Searching #{search_key_word} on google..."
    end
    puts('-----------------------------------------------')
    puts response
    convert_text_to_speech(response,text_to_speech_settings)
    file = File.new('search_result.json','w')
    file.puts serpapi_response
    file.close()
    # if body[]

end

def process_responses(responses,text_to_speech_settings)
	num_chars_printed = 0
    for response in responses
        puts response
        puts '------'
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
        transcript = result.alternatives[0].transcript.downcase

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
            if transcript.match(/time/)
                get_current_time(text_to_speech_settings)
            elsif transcript.match(/day/)
                get_current_date(text_to_speech_settings)
            elsif transcript.match(/weather/)
                get_current_weather(text_to_speech_settings)
            elsif match = transcript.match(/add (?<item>\w+) to/)
                add_item_to_shopping_list(match["item"],text_to_speech_settings)
            elsif transcript.match(/what .+ shopping list/)
                get_shopping_list(text_to_speech_settings)
            elsif match = transcript.match(/(?<search_keyword>(who|what|how|when|where|are|is).+)/)
                search(match['search_keyword'],text_to_speech_settings)
            end
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

def main
    speech_to_text_client , speech_to_text_config = set_up_speech_to_text(:LINEAR16, 16_000, "en-US", true, false)
    text_to_speech_settings = set_up_text_to_speech("en-US","en-GB-Wavenet-A",:LINEAR16)


    microphone = Pocketsphinx::Microphone.new()
    queue_buffer = Queue.new
    
    microphone_start_recording(microphone,queue_buffer)
    stream = microphone_stream(microphone,queue_buffer)
    requests = generate_request(speech_to_text_config,stream)
    responses = speech_to_text_client.streaming_recognize(requests)
	process_responses(responses,text_to_speech_settings)
    microphone_stop_recording(microphone,queue_buffer)

end

main()

