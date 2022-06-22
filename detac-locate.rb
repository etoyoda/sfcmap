require 'json'

class App

  def initialize args
    @stab = []
    @detac = []
    @bt = @ofn = nil
    args.each{|arg|
      case arg
      when /^-nsd=/ then @stab.push($')
      when /^-o=/ then @ofn = $'
      when /^-bt=/ then @bt = $'
      else @detac.push(arg)
      end
    }
    @bt = Time.now.utc unless @bt
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
          @sdb[i2+i3] = { 'name' => n, 'pos' => pos }
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

  def strtof str
    case str
    when /^-?\d+(\.\d+)?$/ then str.to_f
    else nil
    end
  end

  def vis vv
    iv = strtoi(vv)
    case iv
    when 0 then 50
    when 1..55 then iv * 100
    when 56..80 then (iv - 50) * 1000
    when 81..89 then (iv - 74) * 5000
    when 90 then 25
    when 91 then 50
    when 92 then 200
    when 93 then 500
    when 94 then 1000
    when 95 then 2000
    when 96 then 4000
    when 97 then 10_000
    when 98 then 20_000
    when 99 then 50_000
    else nil
    end
  end

  DAY = 86400

  def mktime dcd
    d = strtoi(dcd['YY'])
    h = strtoi(dcd['GG/9']) || strtoi(dcd['GG'])
    n = strtoi(dcd['gg']) || 0
    unless d and h
      if / (\d\d)(\d\d)(\d\d)/ === dcd['AHL'] then
        d = $1.to_i
        h = $2.to_i
        n = $3.to_i
      else
        $stderr.puts dcd.inspect
        raise
        return 'unknown'
      end
    end
    d = [[d, 31].min, 1].max
    xt = @bt
    # 未来日付の観測はないので、 @bt より遡る
    xt -= DAY while d != xt.day
    xt -= DAY if h == 23 and dcd['GG'] == '0'
    d = xt.day
    m = xt.mon
    y = xt.year
    begin
      return Time.gm(y, m, d, h, n).strftime('%Y-%m-%dT%H:%MZ')
    rescue ArgumentError
      $stderr.puts [y, m, d, h, n].inspect
      return "unknown"
    end
  end

  def synopconv xstnid, h, pos, name
    dd = strtoi(h['dd'])
    dd = nil if dd == 99 or dd == 90
    return nil unless dd
    r = {
      "@" => xstnid,
      "La" => pos[0],
      "Lo" => pos[1],
      "d" => dd * 10
    }
    r['ix'] = h['ix']
    v = vis(h['VV']) ; r['V'] = v if v
    f = strtoi(h['ff'])
    f = (f * 5.1444).floor * 0.1 if f and /[34]/ === h['iw']
    r['f'] = f if f
    n = strtoi(h['N'])
    r['N'] = (n * 12.5).floor if n
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
    r
  end

  def tempconv xstnid, h, pos
    keys = h.keys.grep(/^dd@/).map{|s| s.sub(/^dd@/, '')}
    keys.each{|pl|
      r = {
        "@" => xstnid,
        "La" => pos[0],
        "Lo" => pos[1],
        'd' => strtoi(h["dd@#{pl}"])
      }
      sel = "fff@#{pl}"
      r['f'] = strtof(h[sel]) if h.include? sel
      sel = "hhh@#{pl}"
      r['z'] = strtoi(h[sel]) if h.include? sel
      t = strtoi(h["TTTa@#{pl}"])
      r['T'] = Float('%4.1f' % (t * 0.1 + 273.15)) if t
      sel = "DD@#{pl}"
      dd = strtoi(h[sel])
      if dd and r['T'] then
        r['Td'] = r['T'] - dd * 0.1
      end
      yield(pl.sub(/SURF/, 'sfc'), r)
    }
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
          xstnid = pos = name = nil
          case h['@MiMj']
          when 'AAXX', 'TTAA' then
            unless @sdb[stnid]
              $stderr.puts "fixed #{stnid} unlocatable"
              next
            end
            xstnid = stnid
            pos = @sdb[stnid]['pos']
            name = @sdb[stnid]['name']
          else
            xstnid = "v#{stnid}"
            xstnid = "m#{stnid}" if 'IIAA' == h['@MiMj']
            lat = strtoi(h['La.3'])
            lon = strtoi(h['Lo.4'])
            unless lat and lon
              $stderr.puts "mobile #{stnid} unlocatable"
              next
            end
            lat *= 0.1
            lon *= 0.1
            lon += 360 if lon < -30
            pos = [lat, lon]
          end
          key = [mktime(h), 'sfc', xstnid].join('/')
          if stnid != 'SHIP' then
            if @duptab[key]
              $stderr.puts "station #{key} dup"
              next
            end
            @duptab[key] = 1
          end
          case h['@MiMj']
          when 'TTAA','UUAA','IIAA' then
            tempconv(xstnid, h, pos) {|pl, r|
              key2 = [mktime(h), pl, xstnid].join('/')
              @result.push [key2, r]
            }
          else
            r = synopconv(xstnid, h, pos, name)
            next unless r
            @result.push [key, r]
          end
        }
      }
    }
  end

  def saveto ofp
    for key, ent in @result
      json = ent.to_json.gsub(/000000+\d\b/, '')
      ofp.puts([key, json].join(' '))
    end
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
