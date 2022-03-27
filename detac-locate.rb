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
    when /^(\d+)-(\d+)[NE]$/ then
      (($1.to_i + $2.to_i / 60.0) * 100 + 0.5).floor * 0.01
    when /^(\d+)-(\d+)[WS]$/ then
      (-($1.to_i + $2.to_i / 60.0) * 100 + 0.5).floor * 0.01
    else nil
    end
  end

  def latlon(la, lo)
    fla = nwsangle(la)
    flo = nwsangle(lo)
    flo += 360 if flo and flo < 0
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

  def strtoi str
    case str
    when /^-?\d+$/ then str.to_i
    else nil
    end
  end

  def detacload
    @detac.each {|detac|
      File.open(detac, "r:ASCII-8BIT") {|ifp|
        ifp.each_line{|line|
          h = {}
          line.chomp.split(/\t/).each{|kvp|
            k, v = kvp.split(/:/, 2)
            h[k] = v
          }
          stnid = h['stnid'] = h['@ID'].to_s
          next if stnid.empty?
          if stnid != 'SHIP' then
            if @duptab[stnid]
              $stderr.puts "station #{stnid} dup"
              next
            end
            @duptab[stnid] = 1
          end
          pos = name = hha = nil
          if @sdb[stnid] then
            pos = @sdb[stnid]['pos']
            name = @sdb[stnid]['name']
            hha = strtoi(@sdb[stnid]['h'])
          else
            hha = 0
            lat = strtoi(h['La.3'])
            lon = strtoi(h['Lo.4'])
            unless lat and lon
              $stderr.puts "obs #{stnid} unlocatable"
              next
            end
            lat *= 0.1
            lon *= 0.1
            lon += 360 if lon < -30
            pos = [lat, lon]
          end
          dd = strtoi(h['dd'])
          dd = nil if dd == 99 or dd == 90
          next unless dd
          xstnid = if 'BBXX' == h['@MiMj'] then 'v' + stnid else stnid end
          r = {
            "@" => xstnid,
            "La" => pos[0],
            "Lo" => pos[1],
            "d" => dd,
            "h" => hha
          }
          f = strtoi(h['ff'])
          f = (f * 5.1444).floor * 0.1 if f and /[34]/ === h['iw']
          r['f'] = f if f
          n = strtoi(h['N'])
          r['N'] = n if n
          w = strtoi(h['ww'])
          r['w'] = w if w
          t = strtoi(h['TTT'])
          r['T'] = Float('%4.1f' % (t * 0.1 + 273.15)) if t
          t = strtoi(h['Td.3'])
          r['Td'] = Float('%4.1f' % (t * 0.1 + 273.15)) if t
          p4 = strtoi(h['P.4'])
          r['P'] = p4 * 10 if p4
          p0 = strtoi(h['P0.4'])
          r['P0'] = p0 * 10 if p0
          cl = strtoi(h['CL']) ; r['CL'] = cl if cl
          cm = strtoi(h['CM']) ; r['CM'] = cm if cm
          ch = strtoi(h['CH']) ; r['CH'] = ch if ch
          r['#'] = name if name
          r['ahl'] = h['AHL'] if h['AHL']
          @result.push r
        }
      }
    }
  end

  def saveto ofp
    @result.size.times {|i|
      json = @result[i].to_json.gsub(/000000+\d,/, ',')
      ofp.puts json
    }
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
