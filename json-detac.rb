require 'json'

class App

  def initialize args
    @stab = []
    @detac = []
    @vt = @ofn = nil
    args.each{|arg|
      case arg
      when /^-nsd=/ then @stab.push($')
      when /^-o=/ then @ofn = $'
      when /^-vt=/ then @vt = $'
      else @detac.push(arg)
      end
    }
    @sdb =  {}
    @result = []
    @duptab = {}
  end

  def nwsangle(str)
    case str
    when /^(\d+)-(\d+)[NE]$/ then sprintf('%6.2f', $1.to_i + $2.to_i / 60.0).to_f
    when /^(\d+)-(\d+)[WS]$/ then -sprintf('%6.2f', $1.to_i + $2.to_i / 60.0).to_f
    else nil
    end
  end

  def latlon(la, lo)
    fla = nwsangle(la)
    flo = nwsangle(lo)
    return nil unless fla and flo
    [fla, flo]
  end

  def stabload
    if @stab.empty? then
      $stderr.puts 'no station table specified - nsd_bbsss.txt assumed'
      @stab.push 'nsd_bbsss.txt'
    end
    @stab.each {|sfn|
      File.open(sfn, 'r') {|ifp|
        ifp.each_line{|line|
          #47;582;----;Akita;;Japan;2;39-43N;140-06E;39-43N;140-06E;6;21;P^M
	  i2,i3,c4,n,st,ct,ra,la,lo,la,lo2,la2,hha,hp,rem = line.chomp.split(/;/,15)
	  pos = latlon(la, lo) or next
	  next if hha.empty?
	  h = hha.to_i
	  @sdb[i2+i3] = { 'name' => n, 'pos' => pos, 'h' => h }
	}
      }
    }
  end

  def detacload
    @detac.each {|detac|
      File.open(detac, "r") {|ifp|
        ifp.each_line{|line|
	  h = {}
	  line.chomp.split(/\t/).each{|kvp|
	    k, v = kvp.split(/:/, 2)
	    h[k] = v
	  }
	  stnid = h['stnid'] = h['@ID'].to_s
	  next if stnid.empty?
	  unless @sdb[stnid]
	    $stderr.puts "station #{stnid} missing"
	    next
	  end
	  if @duptab[stnid]
	    $stderr.puts "station #{stnid} dup"
	    next
	  end
	  next unless /\d/ === h['dd']
	  r = {
	    "type" => "Feature",
	    "geometry" => { "type" => "Point", "coordinates" => @sdb[stnid]['pos'] },
	    "properties" => {
	      "name" => @sdb[stnid]['name'],
	      "dd" => h['dd'],
	      "ff" => h['ff'],
	      "N" => h['N'],
	      "h" => @sdb[stnid]['h']
	      }
	    }
	  @result.push r
	  @duptab[stnid] = 1
	}
      }
    }
  end

  def saveto ofp
    ofp.write "{ \"type\": \"FeatureCollection\",\n"
    ofp.write "\"x-validtime\": #{@vt.to_json},\n" if @vt
    ofp.write "\"features\": [\n"
    @result.size.times {|i|
      ofp.write ",\n" unless i.zero?
      ofp.write @result[i].to_json
    }
    ofp.write "]}\n"
  end

  def output
    if @ofn
    then
      File.open(@ofn, "w"){|ofp| saveto(ofp) }
    else
      saveto($stdout)
    end
  end

  def run
    stabload
    detacload
    output
  end

end

App.new(ARGV).run
