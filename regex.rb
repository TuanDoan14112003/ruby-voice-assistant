def split_text(text,max_length)
    index = 0
    lines = []
    while (index < text.length)
        puts "Index is #{index}"
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

text="
beautiful is a adjective. It has 2 meanings. 1. pleasing the senses or mind aesthetically. 2. of a very high standard; excellent."
lines = split_text(text,100)
puts lines
