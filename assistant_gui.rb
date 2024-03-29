require 'gosu'
require 'pocketsphinx-ruby'
require "google/cloud/speech"
require "google/cloud/text_to_speech"
require 'gosu'
require 'http'
require 'launchy'
require 'uri'

module ZOrder
  BACKGROUND, MIDDLE, TOP = *0..2
end

class VirtualVoiceAssistantWindow < Gosu::Window

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
        queue_buffer.push(nil)
        @streaming = false
        microphone.stop_recording()
    end
    
    def microphone_stream(microphone, queue_buffer)
        Enumerator.new do |enum|
            while @streaming
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

    def generate_request(stream)
        Enumerator.new do |gen|
            gen.yield Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(streaming_config: @speech_to_text_config)
            for item in stream
                gen.yield Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(audio_content: item)
            end
        end
    end

    def process_responses(responses, microphone,queue_buffer)
        Thread.new {
            num_chars_printed = 0
            for response in responses
                if response.results.length == 0
                    next
                end

                result = response.results[0]
                if result.alternatives.length == 0
                    next
                end
                
                transcript = result.alternatives[0].transcript.downcase
        
             
                
                @user_command = transcript
                @assistant_response = "..."
                
                if result.is_final == true
                    if transcript.match(/time/)
                        assistant_response = get_current_time()
                    elsif transcript.match(/day/)
                        assistant_response = get_current_date()
                    elsif transcript.match(/weather/)
                        assistant_response = get_current_weather()
                    elsif match = transcript.match(/add (?<item>\w+) to/)
                        assistant_response = add_item_to_shopping_list(match["item"],)
                    elsif transcript.match(/(what|what's) .+ shopping list/)
                        assistant_response = get_shopping_list()
                    elsif match = transcript.match(/(?<search_keyword>(who|what|how|when|where|are|is).+)/)
                        assistant_response = search(match['search_keyword'])
                    elsif transcript.match(/exit/)
                        break
                    else
                        assistant_response = get_unknow_command()
                    end
                    @assistant_response = assistant_response
                    microphone_stop_recording(microphone,queue_buffer)
                    num_chars_printed = 0

                    break
                end
            end
        }
    end

    def initialize
        @streaming = false
        @sound = nil
        @WINDOW_WIDTH = 1000
        @WINDOW_HEIGHT = 500
        @WINDOW_BORDER = 30
        
        @assistant_response = ""
        @voice_command = ""
        @speech_to_text_client , @speech_to_text_config = set_up_speech_to_text(:LINEAR16, 16_000, "en-US", true, false)
        @text_to_speech_settings = set_up_text_to_speech("en-US","en-GB-Wavenet-A",:LINEAR16)
        super(@WINDOW_WIDTH, @WINDOW_HEIGHT, false)
        @font = Gosu::Font.new(self, Gosu::default_font_name, 20)
        self.caption = "Virtual Voice Assistant"

    end


    def convert_text_to_speech(response)
        text_to_speech_client,text_to_speech_voice,text_to_speech_config = @text_to_speech_settings
        synthesis_input = Google::Cloud::TextToSpeech::V1::SynthesisInput.new(text: response)
        response = text_to_speech_client.synthesize_speech(input:synthesis_input, voice:text_to_speech_voice, audio_config:text_to_speech_config)
    
        file = File.new("response.wav","wb")
        file.write response.audio_content
        file.close
        
        @sound = Gosu::Sample.new("response.wav")
        @sound.play()
    end

    def get_current_time()
        time = Time.now()
        response = time.strftime("It's %I:%M%p")  
        convert_text_to_speech(response)
        return response
    end
    
    def get_current_date()
        time = Time.now()
        response = time.strftime("Today is %A %B %d, %Y")  
        convert_text_to_speech(response)
        return response
    end
    
    def get_current_weather()
        open_weather_api_key = '31d640b8fa6ce0439aa5e350c5ca6ee0'
        open_weather_uri = "https://api.openweathermap.org/data/2.5/weather?q=Melbourne&units=metric&appid=#{open_weather_api_key}"
        open_weather_response = HTTP.get(open_weather_uri)
        if open_weather_response.status.code == 200
            weather = open_weather_response.parse
            weather_description = weather['weather'][0]['description']
            temp = weather['main']["temp"]
            feels_like_temp = weather['main']["feels_like"]
            humidity = weather["main"]["humidity"]
            wind_speed = weather["wind"]["speed"]
            cloudiness = weather["clouds"]["all"]
            response = "It's currently #{weather_description}. Temperature is #{temp} degrees Celsius, feels like #{feels_like_temp}. Humidity is #{humidity}%. Wind speed is #{wind_speed} meters per second and #{cloudiness}% clouds"
            convert_text_to_speech(response)
        else 
            puts("Bad request: #{response.status.code}")
        end
        return response
    end
    
    def get_shopping_list()
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
        convert_text_to_speech(response)
        return response
    end
    
    def add_item_to_shopping_list(item)
        shopping_list = File.new("shopping_list.txt",'a+')
        item_already_existed = false
        shopping_list.each_line do |line|
            if (line.chop == item)
                item_already_existed = true
            end
        end
        if item_already_existed
            response = "The item is already in your shopping list"
        else
            shopping_list.puts item
            response = "I have added #{item} to your shopping list"
        end
        shopping_list.close()
        convert_text_to_speech(response)
        return response
    end
        
    def search(search_key_word)
        search_query = URI.encode_www_form([['q',search_key_word]])
        uri = "https://google.com/search?" + search_query
        Launchy.open(uri)
        serpapi_key = "6383e617670c68b60eaf5825a8142efd2a0fb91e2abd4e4723b1f3e21944a385"
        uri = "https://serpapi.com/search?api_key=#{serpapi_key}&gl=au&#{search_query}"
        serpapi_response = HTTP.get(uri)
        response_body = serpapi_response.parse
        if response_body["answer_box"] != nil
            answer_box = response_body["answer_box"]
            if answer_box["type"] == "calculator_result"
                response = "The result is: " + response_body["answer_box"]["result"]
            elsif answer_box["type"] == "finance_results"
                company = answer_box["title"]
                stock_price = answer_box["price"].to_s + " " + answer_box["currency"]
                response = "#{company}'s stock is #{stock_price}."
            elsif answer_box["type"] == "population_result"
                place = answer_box["place"]
                population = answer_box["population"]
                response = "The population of #{place} is #{population}"
            elsif answer_box["type"] == "currency_converter"
                original_price = answer_box["currency_converter"]["from"]
                converted_price = answer_box["currency_converter"]["to"]
                response = original_price["price"].to_s + " #{original_price["currency"]} is " + converted_price["price"].to_s + " #{converted_price["currency"]}."
            elsif answer_box["type"] == "dictionary_results"
                word_type = answer_box["word_type"]
                definition_list= answer_box["definitions"]
                response = "#{answer_box["syllables"]} is a #{word_type}. It has #{definition_list.length} meanings. "
                for i in 1..definition_list.length
                    response += " "
                    response += "#{i}. #{definition_list[i-1]}"
                end
            elsif answer_box["type"] == "organic_result"
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
        else 
            response = "Searching #{search_key_word} on google..."
        end

        puts response
        convert_text_to_speech(response)
        return response

    end

    def get_unknow_command()
        response = "I'm sorry, I don't understand, could you repeat that?"
        convert_text_to_speech(response)
        return response
    end

    def draw_background
        Gosu.draw_rect(0, 0, @WINDOW_WIDTH, @WINDOW_HEIGHT, Gosu::Color::AQUA, ZOrder::BACKGROUND, mode=:default)
    end


    def split_text(text,max_length)
        index = 0
        text = text.dup
        lines = []
        while (index < text.length)
            if index+max_length < text.length
                for i in (index+max_length).downto(index)
                    if i == index
                        lines.push(text.slice(index,max_length))
                        index += max_length
                    elsif text[i] == " "
                        text[i] = ""
                        line_length = i - index
                        lines.push(text.slice(index,line_length))
                        index += line_length
                        break
                        
                    end
                end
            else
                lines.push(text.slice(index,max_length))
                index += max_length
            end
        end
        return lines
    end
    
    
    def draw_message_box
        message_box_border = @WINDOW_BORDER
        message_box_start_location = [0 + message_box_border,0 + message_box_border]
        message_box_size = [@WINDOW_WIDTH - message_box_border * 2,@WINDOW_HEIGHT - message_box_border * 2]
        Gosu.draw_rect(message_box_start_location[0],message_box_start_location[1],message_box_size[0],message_box_size[1],Gosu::Color::WHITE, ZOrder::MIDDLE, mode=:default)
        
       
        text = @user_command
        command_wrapper_border = 50
        command_wrapper_start_location = [message_box_start_location[0] + command_wrapper_border, message_box_start_location[1] + command_wrapper_border]
        command_font_border = 10
        @font.draw_text(text,command_wrapper_start_location[0] + command_font_border,command_wrapper_start_location[1] +command_font_border, ZOrder::TOP)
        command_wrapper_size = [@font.text_width(text) + command_font_border *2,@font.height + command_font_border * 2]
        Gosu.draw_rect(command_wrapper_start_location[0],command_wrapper_start_location[1],command_wrapper_size[0],command_wrapper_size[1],Gosu::Color::GREEN, ZOrder::MIDDLE, mode=:default)
        response_text_lines = split_text(@assistant_response,100)
        response_wrapper_border = 50
        response_font_border = 20
        response_wrapper_size = [@font.text_width(response_text_lines[0])  + response_font_border*2,@font.height * response_text_lines.length + response_font_border * 2]
        response_wrapper_start_location = [@WINDOW_WIDTH - message_box_border  - response_wrapper_size[0] - response_wrapper_border , command_wrapper_start_location[1] + command_wrapper_size[1] + response_wrapper_border]
        line_spacing = 20
        line_ypos = 0

        for line in response_text_lines
            @font.draw_text(line,response_wrapper_start_location[0] + response_font_border,response_wrapper_start_location[1] + response_font_border + line_ypos,ZOrder::TOP)
            line_ypos += line_spacing
        end

        Gosu.draw_rect(response_wrapper_start_location[0],response_wrapper_start_location[1],response_wrapper_size[0],response_wrapper_size[1],Gosu::Color::GREEN, ZOrder::MIDDLE, mode=:default)

    end


    def draw_prompt_message(prompt)
        @font.draw_text(prompt, @WINDOW_WIDTH/2 - 100, @WINDOW_BORDER, ZOrder::TOP, 1,1 ,Gosu::Color.argb(0xff_000000) )
    end

    def draw()
        draw_background()
        draw_message_box()
        draw_prompt_message(@prompt)
    end

    def stream()
        @prompt = "You can speak now"
        @streaming = true
        @assistant_response = ""
        microphone = Pocketsphinx::Microphone.new()
        queue_buffer = Queue.new()
        microphone_start_recording(microphone, queue_buffer)
        stream = microphone_stream(microphone, queue_buffer)
        requests = generate_request(stream)
        responses = @speech_to_text_client.streaming_recognize(requests)
        process_responses(responses,microphone, queue_buffer)

    end

    def update()
        if (Gosu.button_down? Gosu::KB_SPACE and @streaming == false)
            stream()
        end
        if @streaming == false
            @prompt = "Press space to speak"
        end
    end

end

window = VirtualVoiceAssistantWindow.new
window.show

# Reference: https://cloud.google.com/speech-to-text/docs/samples/speech-transcribe-streaming-mic#speech_transcribe_streaming_mic-python