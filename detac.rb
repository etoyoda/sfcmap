require 'strscan'

class Hash
  def to_ltsv
    keys.sort.map{|k|
      v = self[k]
      sv = case v when Float then format('%3.1f', v)
        else v.to_s end
      [k, sv].join(':')
    }.join("\t")
  end
  def to_yaml
    ["---", keys.sort.map{|k|
      v = self[k]
      qk = case k when /\A[A-Za-z][-\w\/@.]+\z/n then k
        else "'#{k}'" end
      qv = case v when Float then format('%3.1f', v)
        when Numeric then v.to_s
        when /\A[A-Za-z][-\w\/@.]*\z/n then v
        else "'#{v}'" end
      [qk, qv].join(': ')
    }].join("\n")
  end
end

class Tac

  def self.atoi str
    case str
    when /^\d+$/n then str.to_i
    when /^0?\/+$/n then '/'
    when /^[0-9][0-9]+\/+$/n then str.tr('/', '0').to_i
    else '*'
    end
  end

  # snTTT of FM 12 SYNOP etc - top digit is sign
  def self.atosi sgn, str
    i = atoi(str)
    return i unless Integer === i
    case sgn
    when /^0$/n then i
    when /^1$/n then -i
    else '/'
    end
  end

  # TTTa of FM 35 TEMP etc - last digit odd if negative
  def self.atoia str
    case str
    when /^\d*[02468]$/n then str.to_i
    when /^\d*[13579]$/n then -str.to_i
    when /\//n then '/'
    else '*'
    end
  end

  # DD of FM 35 TEMP etc - unit depends on top digit
  def self.atoDD str
    case str
    when /^[5-9]\d+$/n then str.to_i - 50
    when /^\d*$/n then str.to_i * 0.1
    when /\//n then '/'
    else '*'
    end
  end

  # ddfff of FM 35 TEMP etc - middle digit +5'ed to represent 5 degree
  # returns array [direction/deg, wind speed]
  def self.atoddfff str
    case str
    when /\A[0-9][0-9][56789][0-9][0-9]\z/n then
      [str[0,2].to_i * 10 + 5, str[2,3].to_i - 500] 
    when /[0-9]{5}\z/n then
      [str[0,2].to_i * 10, str[2,3].to_i] 
    else
      ['/', '/']
    end
  end

  # PPPP etc of FM 71 CLIMAT
  def self.atoPPPP str
    case str
    when /^0\d+$/n then str.to_i + 10_000
    when /^\d+$/n then str.to_i
    when /^\/+$/n then '/'
    else '*'
    end
  end

  # stubs to be overriden
  def ex_init; nil end
  def decode; nil end
  def heritage; nil end
  def heritage= val; nil end

  def initialize(ahl, mimj, heritage)
    @ahl = ahl
    @mimj = mimj
    @hold = []
    @fnam = nil
    @hold.push heritage if heritage
    @dcd = { "AHL" => @ahl, "@MiMj" => @mimj }
    @msgs = []
    @frozen = nil
    @state = nil
    @z = nil
    ex_init()
  end

  def eputs msg
    h = {'!'=>'ERR', 'AHL'=>@ahl, 'MiMj'=>@mimj, 'ID'=>@dcd['@ID'], '~'=>msg}
    @msgs.push [nil, h]
    true
  end

  def wputs msg
    h = {'!'=>'WRN', 'AHL'=>@ahl, 'MiMj'=>@mimj, 'ID'=>@dcd['@ID'], '~'=>msg}
    @msgs.push [nil, h]
    true
  end

  def fnam= val
    @fnam = val
  end

  def push ttype, token
    throw(:BUG, "push(#{ttype}, #{token}) after freeze") if @frozen
    @hold.push token
  end

  def flush callback
    return if @frozen
    @dcd['~'] = @hold.join(' ')
    decode
    @msgs.each { |tag, val| callback.call(tag, val) }
    callback.call(@mimj, @dcd)
    @frozen = true
  end

  class METAR < self

    def decode
      @dcd['@ID'] = @hold[0]
      @dcd['@ID'] = @hold[1] if /^COR$/n === @dcd['@ID']
    end

  end

  SPECI = METAR

  # SHIP
  class BBXX < self

    State = {
      nil => :D_D,
      :YYGGi => :_99LLL,
      :QLLLL => :iihVV,
      :hhhhi => :iihVV
    }

    REG_YYGGi = /^([012][0-9]|3[01])([01][0-9]|2[0-3])[0134\/]/n

    # these groups are recognised without condition
    def dcd_preempt(group)
      case group
      when /^(?:NIL|nil)$/n then return (@state = :nil)
      when /^555$/n then return (@state = :sec5)
      end
      nil
    end

    # sections 0 and 1 are decoded by position
    def dcd_bypos(i, group)
      hit = case @state
	when :D_D
	  group2 = @hold[i+1]
          if REG_YYGGi =~ group and /^99/n =~ group2
	    @dcd['@ID'] = '*'
	    @dcd['YY'] = Tac.atoi(group[0, 2])
	    @dcd['GG'] = Tac.atoi(group[2, 2])
	    @dcd['iw'] = Tac.atoi(group[4, 1])
	    @state = self.class::State[:YYGGi]
	  else
	    @dcd['@ID'] = group
	    @state = :YYGGi
	  end
	when :YYGGi
	  case group
	  when REG_YYGGi then
	    @dcd['YY'] = Tac.atoi(group[0, 2])
	    @dcd['GG'] = Tac.atoi(group[2, 2])
	    @dcd['iw'] = Tac.atoi(group[4, 1])
	    @state = self.class::State[@state]
	  when /^HSSS$/n then
	    wputs("ignored (#{group}) where YYGGi expected")
	  else
	    eputs("stop word (#{group}) where YYGGi expected")
	    @state = :err
	  end
	when :IIiii
	  @dcd['@ID'] = group
          @state = self.class::State[@state]
	when :_99LLL
	  @dcd['La.3'] = Tac.atoi(group[2, 3])
	  @state = :QLLLL
	when :QLLLL
	  @dcd['Qc'] = Tac.atoi(group[0, 1])
	  @dcd['Lo.4'] = Tac.atoi(group[1, 4])
          @state = self.class::State[@state]
	when :MMMUU
	  @dcd['MMM'] = Tac.atoi(group[0, 3])
	  @dcd['ULa'] = Tac.atoi(group[3, 1])
	  @dcd['ULo'] = Tac.atoi(group[4, 1])
	  @state = :hhhhi
	when :hhhhi
	  h = Tac.atoi(group[0, 4])
	  @dcd['im'] = im = Tac.atoi(group[4, 1])
	  if Integer === h
	    case im
	    when 5..8 then h = (h * 0.3048 + 0.5).floor
	    end
	  end
	  @dcd['h0.4'] = h
          @state = self.class::State[@state]
	when :iihVV
	  @dcd['iR'] = Tac.atoi(group[0, 1])
	  @dcd['ix'] = Tac.atoi(group[1, 1])
	  @dcd['h'] = Tac.atoi(group[2, 1])
	  @dcd['VV'] = Tac.atoi(group[3, 2])
	  @state = :Nddff
	when :_0ddff
	  @dcd['dd'] = Tac.atoi(group[1, 2])
	  @dcd['ff'] = Tac.atoi(group[3, 2])
	  @state = :sec1
	when :Nddff
	  @dcd['N'] = Tac.atoi(group[0, 1])
	  @dcd['dd'] = Tac.atoi(group[1, 2])
	  @dcd['ff'] = Tac.atoi(group[3, 2])
	  @state = :sec1
	end
      hit
    end

    # tokens causing state change - recognised only after "bypos" is done
    def dcd_secleader(group)
      hit = case group
      when /^222[0-9\/][0-9\/]$/n then
	@state = :sec2
      when /^222$/n then
	@state = :sec2
      when /^333$/n then
	@state = :sec3
      when /^444$/n then
	@state = :sec4
      when /^55$/n then
	wputs("(55) for (555)")
	@state = :sec5
      when /^(REMARKS|CHECK)$/n then
	eputs("stop word (#{group}) in #{@state}")
	@state = :err
      end
      hit
    end

    # the rest of decode
    def dcd_main(group)
      if :sec1 === @state then
	case group
	when /^00(...)/n then @dcd['ff'] = Tac.atoi($1)
	when /^1(.)(...)/n then @dcd['TTT'] = Tac.atosi($1, $2)
	when /^29(...)/n then @dcd['UUU'] = Tac.atoi($1)
	when /^2(.)(...)/n then @dcd['Td.3'] = Tac.atosi($1, $2)
	when /^3(....)/n then
	  v = Tac.atoi($1)
	  case v
	  when String then :ignore
	  when 0..799 then v += 10_000
	  when 800..900 then v += 9000
	  end
	  @dcd['P0.4'] = v
	when /^4([09\/]...)/n then
	  v = Tac.atoi($1)
	  case v
	  when String then :ignore
	  when 0..799 then v += 10_000
	  when 800..900 then v += 9000
	  end
	  @dcd['P.4'] = v
	when /^4([12578])(...)/n then
	  @dcd['a3'] = Tac.atoi(group[1, 1])
	  @dcd['hhh'] = Tac.atoi(group[2, 3])
	when /^40[0-9][0-9]$/n then
	  wputs("sec1 - zero inserted (#{group}) for 4PPPP")
	  @dcd['P.4'] = Tac.atoi(group[1, 3]) + 10_000
	when /^5(.)(...)/n then
	  a, ppp = $1, $2
	  @dcd['a'] = Tac.atoi(a)
	  @dcd['ppp'] = Tac.atoi(ppp)
	  if /^[5-8]/n === a and Numeric === @dcd['ppp'] then
	    @dcd['ppp'] = -@dcd['ppp']
	  end
	when /^6(...)(.)/n then
	  @dcd['RRR'] = Tac.atoi(group[1, 3])
	  @dcd['t'] = Tac.atoi(group[4, 1])
	when /^7(..)(.)(.)/n then
	  @dcd['ww'] = Tac.atoi(group[1, 2])
	  @dcd['W1'] = Tac.atoi(group[3, 1])
	  @dcd['W2'] = Tac.atoi(group[4, 1])
	when /^8(.)(.)(.)(.)/n then
	  @dcd['Nh'] = Tac.atoi(group[1, 1])
	  @dcd['CL'] = Tac.atoi(group[2, 1])
	  @dcd['CM'] = Tac.atoi(group[3, 1])
	  @dcd['CH'] = Tac.atoi(group[4, 1])
	when /^9[0-9\/]{4}$/n then
	  @dcd['GG/9'] = Tac.atoi(group[1, 2])
	  @dcd['gg'] = Tac.atoi(group[3, 2])
	when /^\/\/\/\/\/$/n then
	  :ignore
	else
	  eputs("sec1 - bad group (#{group})")
	end
      elsif :sec2 === @state then
	case group
	when /^0([0246\/])(...)$/n then
	  @dcd['ss'] = Tac.atoi(group[1, 1])
	  @dcd['Tw.3'] = Tac.atoi(group[2, 3])
	when /^0([1357])(...)$/n then
	  @dcd['ss'] = Tac.atoi(group[1, 1])
	  @dcd['Tw.3'] = Tac.atosi('1', group[2, 3])
	when /^1....$/n then
	  @dcd['PwaPwa'] = Tac.atoi(group[1, 2])
	  @dcd['HwaHwa'] = Tac.atoi(group[3, 2])
	when /^2....$/n then
	  @dcd['PwPw'] = Tac.atoi(group[1, 2])
	  @dcd['HwHw'] = Tac.atoi(group[3, 2])
	when /^3....$/n then
	  @dcd['dw1dw1'] = Tac.atoi(group[1, 2])
	  @dcd['dw2dw2'] = Tac.atoi(group[3, 2])
	when /^4....$/n then
	  @dcd['Pw1Pw1'] = Tac.atoi(group[1, 2])
	  @dcd['Hw1Hw1'] = Tac.atoi(group[3, 2])
	when /^5....$/n then
	  @dcd['Pw2Pw2'] = Tac.atoi(group[1, 2])
	  @dcd['Hw2Hw2'] = Tac.atoi(group[3, 2])
	when /^6....$/n then
	  @dcd['Is'] = Tac.atoi(group[1, 1])
	  @dcd['EsEs'] = Tac.atoi(group[2, 2])
	  @dcd['Rs'] = Tac.atoi(group[4, 1])
	when /^70...$/n then
	  @dcd['Hwa.3'] = Tac.atoi(group[2, 3])
	when /^8(.)(...)$/n then
	  @dcd['Tb.3'] = Tac.atosi($1, $2)
	when /^\/{5}$/n then
	  :ignore
	when /^ICING$/n then
	  @dcd['ICING'] = []
	  @state = :sec2icing
	when /^ICE[0-9\/]{5}$/n then
	  @dcd['ICE'] = [group[3, 5]]
	when /^ICE$/n then
	  @dcd['ICE'] = []
	  @state = :sec2ice
	else
	  wputs("sec2 - bad group (#{group})")
	end
      elsif :sec2icing === @state then
	@dcd['ICING'] << group
      elsif :sec2ice === @state then
	@dcd['ICE'] << group
      elsif :sec3 === @state then
	case group
	when /^0..../n then :ignore
	end
      elsif :sec4 === @state then
      elsif :sec5 === @state then
      end
    end

    # correcion of coordinate sign and post-decode correction
    def dcd_fixup
      case @dcd['Qc']
      when 1 then :ignore
      when 3 then
        @dcd['La.3'] *= -1 if Numeric === @dcd['La.3']
      when 5 then
        @dcd['La.3'] *= -1 if Numeric === @dcd['La.3']
        @dcd['Lo.4'] *= -1 if Numeric === @dcd['Lo.4']
      when 7 then
        @dcd['Lo.4'] *= -1 if Numeric === @dcd['Lo.4']
      end
      for kw in %w(ICING ICE)
	@dcd[kw] = @dcd[kw].join(' ') if @dcd.include?(kw)
      end
    end

    def decode
      @state = self.class::State[nil]
      puts "@ state := #{@state}" if $DEBUG
      @hold.size.times {|i|
        group = @hold[i]
	hit = dcd_preempt(group)
	next if hit
        # section 0 and 1
	hit = dcd_bypos(i, group)
	puts "@ #{group} -> #{@state}" if hit and $DEBUG
	next if hit
	# section leader group
	hit = dcd_secleader(group)
	next if hit
	# section contents
	dcd_main(group)
      }
      dcd_fixup
    end

  end

  # SYNOP MOBILE
  class OOXX < BBXX

    State = BBXX::State.dup
    State[:QLLLL] = :MMMUU 

  end

  # SYNOP
  class AAXX < BBXX

    def heritage
      case @hold.first
      when /^HSSS$/n then @hold[1]
      else @hold.first
      end
    end

    def heritage= val
      @hold.push val if val
    end

    State = BBXX::State.dup
    State[nil] = :YYGGi 
    State[:YYGGi] = :IIiii 
    State[:IIiii] = :iihVV 

  end

  # BUOY
  class ZZYY < BBXX

    State = BBXX::State.dup
    State[nil] = :StationID

    def dcd_bypos i, group
      hit = case @state
      when :StationID
	@dcd['@ID'] = group
	@state = :YYMMJ
      when :YYMMJ
	@dcd['YY'] = Tac.atoi(group[0, 2])
	@dcd['MM'] = Tac.atoi(group[2, 2])
	@dcd['J'] = Tac.atoi(group[4, 1])
	@state = :GGggi
      when :GGggi
	@dcd['GG'] = Tac.atoi(group[0, 2])
	@dcd['gg'] = Tac.atoi(group[2, 2])
	@dcd['iw'] = Tac.atoi(group[4, 1])
	@state = :QLLLLLa
      when :QLLLLLa
	@dcd['Qc'] = Tac.atoi(group[0, 1])
	@dcd['La.5'] = Tac.atoi(group[1, 5])
	@state = :LLLLLL
      when :LLLLLL
	@dcd['Lo.6'] = Tac.atoi(group)
	@state = :_6QQQ_
      when :_6QQQ_
	if /^6...\//n === group then
	  @dcd['Ql'] = Tac.atoi(group[1, 1])
	  @dcd['Qt'] = Tac.atoi(group[2, 1])
	  @dcd['Qa'] = Tac.atoi(group[3, 1])
	  true
	else
	  nil
	end
      end
      hit
    end

    def dcd_secleader group
      hit = case group
      when /^111[0-9\/][0-9\/]$/n then
	@dcd['Qd_1'] = Tac.atoi(group[3, 1])
	@dcd['Qx_1'] = Tac.atoi(group[4, 1])
	@state = :sec1
      when /^222[0-9\/][0-9\/]$/n then
	@dcd['Qd_2'] = Tac.atoi(group[3, 1])
	@dcd['Qx_2'] = Tac.atoi(group[4, 1])
	@state = :sec2
      when /^333[0-9\/][0-9\/]$/n then
	@dcd['Qd1'] = Tac.atoi(group[3, 1])
	@dcd['Qx2'] = Tac.atoi(group[4, 1])
	@state = :sec3
      when /^444$/n then
	@state = :sec4
      when /^555$/n then
	@state = :sec5
      end
      hit
    end

    def dcd_fixup
      case @dcd['Qc']
      when 1 then :ignore
      when 3 then @dcd['La.5'] *= -1
      when 5 then @dcd['La.5'] *= -1; @dcd['Lo.6'] *= -1
      when 7 then @dcd['Lo.6'] *= -1
      end
    end

    def dcd_main(group)
      if :sec1 === @state
	case group
	when /^0..../n then
	  @dcd['dd'] = Tac.atoi(group[1, 2])
	  @dcd['ff'] = Tac.atoi(group[3, 2])
	when /^1([01\/])(...)/n then
	  @dcd['TTT'] = Tac.atosi($1, $2)
	when /^29(...)/n then
	  @dcd['UUU'] = Tac.atoi($1)
	when /^2([01\/])(...)/n then
	  @dcd['Td.3'] = Tac.atosi($1, $2)
	when /^3(....)/n then
	  v = Tac.atoi($1)
	  case v
	  when String then :ignore
	  when 0..799 then v += 10_000
	  when 800..900 then v += 9000
	  end
	  @dcd['P0.4'] = v
	when /^4([09\/]...)/n then
	  v = Tac.atoi($1)
	  case v
	  when String then :ignore
	  when 0..799 then v += 10_000
	  when 800..900 then v += 9000
	  end
	  @dcd['P.4'] = v
	when /^5(.)(...)/n then
	  a, ppp = $1, $2
	  @dcd['a'] = Tac.atoi(a)
	  @dcd['ppp'] = Tac.atoi(ppp)
	  if /^[5-8]/n === a and Numeric === @dcd['ppp'] then
	    @dcd['ppp'] = -@dcd['ppp']
	  end
	end
      elsif :sec2 === @state
	case group
	when /^0([01\/])(...)$/n then
	  @dcd['Tw.3'] = Tac.atosi($1, $2)
	when /^1....$/n then
	  @dcd['PwaPwa'] = Tac.atoi(group[1, 2])
	  @dcd['HwaHwa'] = Tac.atoi(group[3, 2])
	when /^20...$/n then
	  @dcd['Pwa.3'] = Tac.atoi(group[2, 3])
	when /^21...$/n then
	  @dcd['Hwa.3'] = Tac.atoi(group[2, 3])
	end
      elsif :sec3 === @state
	case group
	when /^8887(.)/n then
	  @dcd['k2'] = Tac.atoi($1)
	  z = nil
	  @state = :sec3TS
	when /^66.9./n then
	  @dcd['k6'] = Tac.atoi(group[2, 1])
	  @dcd['k3'] = Tac.atoi(group[4, 1])
	  z = nil
	  @state = :sec3dc1
	else
	  eputs("bad (#{group}) in Sec3")
	end
      elsif :sec3TS === @state
	case group
	when /^2..../n then z = Tac.atoi(group[1, 4])
	when /^3..../n then @dcd['T0@%u' % z.to_i] = Tac.atoi(group[1, 4])
	when /^4..../n then @dcd['S0@%u' % z.to_i] = Tac.atoi(group[1, 4])
	else eputs("sec3TS (#{group})")
	end
      elsif :sec3dc1 === @state
	case group
	when /^2..../n then
	  z = Tac.atoi(group[1, 4])
	  @state = :sec3dc2
	else eputs("sec3dc1 (#{group})")
	end
      elsif :sec3dc2 === @state
	@dcd['d0@%u' % z] = Tac.atoi(group[0, 2])
	@dcd['c0@%u' % z] = Tac.atoi(group[2, 3])
	@state = :sec3dc1
      end
    end

  end

  # TEMP SHIP Part A
  class UUAA < BBXX

    State = {
      nil => :D_D,
      :YYGGi => :_99LLL,
      :QLLLL => :MMMUU,
      :MMMUU => :temp2ini,
    }
    TPrefix = 't'
    WPrefix = 'w'
    Idname = 'Id'
    PFactor = 10
    LevelBase = '00'

    # PPP in TEMP Parts A and B
    def self.atoPPP str
      case str
      when /\A0[0-9][0-9]\z/n then
	1000 + str.to_i
      when /\A[1-9][0-9][0-9]\z/n then
	str.to_i
      else
	'/'
      end
    end

    # "i" is "id" that can be any digit or solidus
    # YY is shifted +50 if wind is reported in knots
    # id is omitted in RUHB
    REG_YYGGi = /^([012567][0-9]|[38][01])([01][0-9]|2[0-3])[0-9\/]?/n

    def dcd_bypos(i, group)
      hit = case @state
	when :D_D
	  @dcd['@ID'] = group
	  @state = :YYGGi
	when :YYGGi
	  if !(@dcd['@ID']) and /^NIL$/n === @hold[i+1] and /^5/n === group then
	    @dcd['@ID'] = group
	    wputs("missing YYGGi")
	    @state = :YYGGi
	  elsif REG_YYGGi === group then
	    @dcd['YY'] = Tac.atoi(group[0, 2])
	    @dcd['GG'] = Tac.atoi(group[2, 2])
	    @dcd[self.class::Idname] = Tac.atoi(group[4, 1])
            wputs("Id omitted") if $DEBUG and group.length == 4
	    @state = self.class::State[@state]
	  elsif '/////' == group then
	    @dcd['YY'] = @dcd['GG'] = '/'
	    @dcd[self.class::Idname] = '/'
	    @state = self.class::State[@state]
	  else
	    eputs("stop word (#{group}) where YYGGi expected")
	    @state = :err
	  end
          @state
	when :IIiii
	  @dcd['@ID'] = group
          @state = self.class::State[@state]
	when :_99LLL
	  @dcd['La.3'] = Tac.atoi(group[2, 3])
	  @state = :QLLLL
	when :QLLLL
	  @dcd['Qc'] = Tac.atoi(group[0, 1])
	  @dcd['Lo.4'] = Tac.atoi(group[1, 4])
          @state = self.class::State[@state]
	when :MMMUU
	  @dcd['MMM'] = Tac.atoi(group[0, 3])
	  @dcd['ULa'] = Tac.atoi(group[3, 1])
	  @dcd['ULo'] = Tac.atoi(group[4, 1])
          @state = self.class::State[@state]
	when :hhhhi
	  h = Tac.atoi(group[0, 4])
	  @dcd['im'] = im = Tac.atoi(group[4, 1])
	  if Integer === h
	    case im
	    when 5..8 then h = (h * 0.3048 + 0.5).floor
	    end
	  end
	  @dcd['h0.4'] = h
          @state = self.class::State[@state]
	else
	  nil
	end
      hit
    end

    # tokens causing state change - recognised only after "bypos" is done
    def dcd_secleader(group)
      hit = case group
      when /^21212$/n then :temp6ini
      when /^31313$/n then :temp7
      when /^41414$/n then :temp8
      when /^51515$/n then :temp91
      when /^61616$/n then :temp101
      when /^62626$/n then :temp102
      end
      @state = hit if hit
      hit
    end

    def atohhh(str, p)
      i = Tac.atoi(str)
      return i if String === i
      case p
      when 10 then (i < 500) ? (30000 + 10 * i) : (20000 + 10 * i)
      when 10...50 then (20000 + 10 * i)
      when 50 then (i < 500) ? (20000 + 10 * i) : (10000 + 10 * i)
      when 50...225 then (20000 + 10 * i)
      when 225...350 then (i < 500) ? (10000 + 10 * i) : (10 * i)
      when 350..500 then 10 * i
      when 500...650 then (i < 500) ? (4000 + i) : (3000 + i)
      when 650...750 then (i < 500) ? (3000 + i) : (2000 + i)
      when 750...825 then (i < 500) ? (2000 + i) : (1000 + i)
      when 825...890 then 1000 + i
      when 890...990 then i
      when 990...1010 then (i < 500) ? i : (500 - i)
      else
        30000 + 10 * i
      end
    end

    # FM 36 TEMP SHIP Sections 2--10
    def dcd_main(group)
      istate = @state
      case @state
      when :temp2ini, :temp2skip, :temp3ini
        case group
        # 7 hPa is reported at least by Canada and U.S.
	when /^(00|92|85|70|50|40|30|25|20|15|10|07)/n then
	  z = Tac.atoi(group[0,2])
          case z
          when 0 then z = 1000
          when 92 then z = 925
          when Numeric then z *= self.class::PFactor
          end
	  @z = "p#{z}"
	  @dcd['hhh@' + @z] = atohhh(group[2,3], z)
	  @state = :temp2TTTDD
	when /^99/n then
	  @z = 'SURF'
	  @dcd['PPP@' + @z] = self.class::atoPPP(group[2,3])
	  @state = :temp2TTTDD
        when /\A88999\z/n then
	  @z = 'TROP'
          while @dcd["PPP@#{@z}"]
            @z = @z.succ
          end
          @dcd["PPP@#{@z}"] = '/'
	  @state = :temp3ini
	when /\A88/n then
	  @z = 'TROP'
          while @dcd["PPP@#{@z}"]
            @z = @z.succ
          end
	  h = self.class::atoPPP(group[2,3])
	  @dcd["PPP@#{@z}"] = h
	  @state = :temp3TTTDD
        when /\A77999\z/n then
          @dcd["PPP@MAXW"] = '/'
          @state = :temp2ini
	when /^(66|77)/n then
	  @z = 'MAXW'
	  @dcd['TOP@' + @z] = 1 if /^66/n === group
	  h = self.class::atoPPP(group[2,3])
	  @dcd['PPP@' + @z] = h
	  @state = :temp4
	#when /\A(44|55)/n then
        when /\A\/{5}\z/n then
          :ignore
	else
          if not :temp3ini === @state
            eputs("stop word (#{group}) in :temp2ini")
	    @state = :err
          end
	end
      when :temp2TTTDD
        @dcd['TTTa@' + @z] = Tac.atoia(group[0,3])
        @dcd['DD@' + @z] = Tac.atoDD(group[3,2])
	@state = (@dcd['%noWind'] ? :temp2skip : :temp2ddfff)
        case @dcd['Id']
        when 5 then @dcd['%noWind'] = @z if /^p50/n === @z
        when 4 then @dcd['%noWind'] = @z if /^p400/n === @z
        when 3 then @dcd['%noWind'] = @z if /^p30/n === @z
        when 2 then @dcd['%noWind'] = @z if /^p20/n === @z
        end
      when :temp3TTTDD
        @dcd['TTTa@' + @z] = Tac.atoia(group[0,3])
        @dcd['DD@' + @z] = Tac.atoDD(group[3,2])
        @state = :temp3ddfff
      when :temp2ddfff
	dd = Tac.atoi(group[0,2])
        if Integer === dd and dd > 36 then
          if dd == 88 then
            @z = 'TROP'
          else
            @z = format('p%u', dd * PFactor)
	    @dcd['%noWind'] = @z unless @dcd['%noWind']
	  end
	  h = Tac.atoi(group[2,3])
          h = '/' if h == 999
	  @dcd["PP@#{@z}"] = h
	  @state = :temp2TTTDD
	else
          @dcd["dd@#{@z}"], @dcd["fff@#{@z}"] = Tac.atoddfff(group)
	  @state = :temp2ini
	end
      when :temp3ddfff
        @dcd["dd@#{@z}"], @dcd["fff@#{@z}"] = Tac.atoddfff(group)
      when :temp4
        case group
	when /^[0123]/n then
          @dcd["dd@#{@z}"], @dcd["fff@#{@z}"] = Tac.atoddfff(group)
	when /^4/n then
          @dcd['vbvb@' + @z] = Tac.atoi(group[1,2])
          @dcd['vava@' + @z] = Tac.atoi(group[3,3])
	end
      when :temp5ini
        if /\A([0-9])\1/n === group
	  irep = self.class::LevelBase
	  begin
	    @z = [self.class::TPrefix, irep, group[0,1]].join
	    irep = irep.succ
	  end while @dcd["PPP@#{@z}"]
	  @dcd["PPP@#{@z}"] = self.class::atoPPP(group[2,3])
	  @state = :temp5TTTDD
	else
          eputs("unknown (#{group}) in TEMP Sec5")
        end
      when :temp5TTTDD
	t = Tac.atoia(group[0,3])
        @dcd['TTTa@' + @z] = t
        @dcd['DD@' + @z] = Tac.atoDD(group[3,2])
	@state = :temp5ini
      when :temp6ini
        if /\A([0-9])\1/n === group
	  irep = self.class::LevelBase
	  begin
	    @z = [self.class::WPrefix, irep, group[0,1]].join
	    irep = irep.succ
	  end while @dcd["PPP@#{@z}"]
	  @dcd["PPP@#{@z}"] = self.class::atoPPP(group[2,3])
	  @state = :temp6ddfff
	else
          eputs("unknown (#{group}) in TEMP Sec6")
        end
      when :temp6ddfff
        @dcd["dd@#{@z}"], @dcd["fff@#{@z}"] = Tac.atoddfff(group)
	@state = :temp6ini
      when :temp7
        case group
	when /^[0-7]/n then
	  @dcd['sr'] = Tac.atoi(group[0,1])
	  @dcd['rara'] = Tac.atoi(group[1,2])
	  @dcd['SaSa'] = Tac.atoi(group[3,2])
	when /^8/n then
	  @dcd['GG/7'] = Tac.atoi(group[1,2])
	  @dcd['gg/7'] = Tac.atoi(group[3,2])
	when /^9/n then
	  @dcd['TwTwTw'] = Tac.atosi(group[1,1], group[2,3])
	end
      when :temp8
        @dcd['Nh'] = Tac.atoi(group[0,1])
        @dcd['CL'] = Tac.atoi(group[1,1])
        @dcd['h'] = Tac.atoi(group[2,1])
        @dcd['CM'] = Tac.atoi(group[3,1])
        @dcd['CH'] = Tac.atoi(group[4,1])
      when :temp91
        case group
        when /\A101([45][0-9])\z/n then @dcd['Err/4'] = Tac.atoi($1)
        when /\A1018([012])\z/n then @dcd['Corr/4'] = Tac.atoi($1)
        when /\A10164\z/n then @state = :temp91na64
        when /\A10190\z/n then @state = :temp91na90
        when /\A10194\z/n then @state = :temp91na94
        when /\A10196\z/n then @state = :temp91na96
        when /\A11[0-9]{3}\z/n then
          @dcd['PPP@h900'] = self.class::atoPPP(group[2,3])
          @state = :temp91hk1
        when /\A77[0-9]{3}\z/n then
          @dcd['hhh@p775'] = atohhh(group[2,3], 775)
          @state = :temp91af1
        when /\A92[0-9\/]{3}\z/n then
          @dcd['hhh@p92x'] = atohhh(group[2,3], 925)
          @state = :temp91af11
        else
          eputs("unknown (#{group}) in Sec9")
        end
      when :temp91na64
        case group
	when /\A000(?:50|[0-4]\d)\z/n then
	  @dcd['LI/4'] = group.to_i
	when /\A\d+\z/n then
	  @dcd['LI/4'] = 50 - group.to_i
	else
	  eputs("unknown (#{group}) in Sec9 RA4 64")
	end
	@state = :temp91
      when :temp91na90
        z = Tac.atoi(group[0,2])
        @dcd["hhh@xp#{z}"] = atohhh(group[2,3], z)
        @state = :temp91
      when :temp91na94
        z = 'h..1500'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp91na94b
      when :temp91na94b
        z = 'h..3000'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp91
      when :temp91na96
        @z = Tac.atoi(group[0,2]) * 10
        @dcd["hhh@ep#{@z}"] = atohhh(group[2,3], @z)
        @state = :temp91na96TTTDD
      when :temp91na96TTTDD
        @dcd["TTTa@ep#{@z}"] = Tac.atoia(group[0,3])
        @dcd["DD@ep#{@z}"] = Tac.atoDD(group[3,2])
        @state = :temp91na96ddfff
      when :temp91na96ddfff
        @dcd["dd@ep#{@z}"], @dcd["fff@ep#{@z}"] = Tac.atoddfff(group)
        @z = nil
        @state = :temp91na96
      when :temp91hk1
        z = 'h900'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp91hk2
      when :temp91hk2
        case group
        when '22800' then @state = :temp91hk3
        when '33600' then @state = :temp91hk5
        else
          eputs("unexpected (#{group}) in TEMP Sec9 11.2")
          @state = :err
        end
      when :temp91hk3
        z = 'p800'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp91hk4
      when :temp91hk4
        if group == '33600' then @state = :temp91hk5
        else
          eputs("unexpected (#{group}) in TEMP Sec9 11.4")
          @state = :err
        end
      when :temp91hk5
        z = 'p600'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp91
      when :temp91af11
        @dcd['TTTa@p92x'] = Tac.atoia(group[0,3])
        @dcd['DD@p92x'] = Tac.atoDD(group[3,2])
        @state = :temp91af12
      when :temp91af12
        z = 'p92x'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp91af13
      when :temp91af13
        if /^77/n === group
          @dcd['hhh@p775'] = atohhh(group[2,3], 775)
          @state = :temp91af1
        else
          eputs("unexpected (#{group}) in TEMP Sec9 92.3")
          @state = :err
        end
      when :temp91af1
        @dcd['TTTa@p775'] = Tac.atoia(group[0,3])
        @dcd['DD@p775'] = Tac.atoDD(group[3,2])
        @state = :temp91af2
      when :temp91af2
        z = 'p775'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp91af3
      when :temp91af3
        if /^60/n === group
          @dcd['hhh@p600'] = atohhh(group[2,3], 600)
          @state = :temp91af4
        else
          eputs("unexpected (#{group}) in TEMP Sec9 77.3")
          @state = :err
        end
      when :temp91af4
        @dcd['TTTa@p600'] = Tac.atoia(group[0,3])
        @dcd['DD@p600'] = Tac.atoDD(group[3,2])
        @state = :temp91af5
      when :temp91af5
        z = 'p600'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp91
      when :temp101
        case group
        when /\A11999\z/n then
          @state = :temp101jp1
        when /\A11[0-9\/]{3}\z/n then
          @dcd['PPP@s10v1'] = Tac.atoi(group[2,3])
          @state = :temp101fr1
        else
          @dcd['_sec10'] = [] unless @dcd['_sec10']
          @dcd['_sec10'].push group
        end
      when :temp101fr1
        z = 's10v1'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp101fr2
      when :temp101jp1
        z = 'p900'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp101jp2
      when :temp101jp2, :temp101fr2
        case group
        when /\A22800\z/n then
          @state = :temp101jp3
        when /\A22[0-9\/]{3}\z/n then
          @dcd['PPP@s10v2'] = Tac.atoi(group[2,3])
          @state = :temp101fr3
        else
          eputs("unexpeted (#{group}) in TEMP Sec10 11.2")
          @state = :temp101
        end
      when :temp101jp3
        z = 'p800'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp101jp4
      when :temp101jp4
        if group == '33600' then
          @state = :temp101jp5
        else
          eputs("unexpeted (#{group}) in TEMP Sec10 11.4")
          @state = :temp101
        end
      when :temp101jp5
        z = 'p600'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp101
      when :temp101fr3
        z = 's10v2'
        @dcd["dd@#{z}"], @dcd["fff@#{z}"] = Tac.atoddfff(group)
        @state = :temp101
      end
      puts "@ #{group}: #{istate} -> #{@state}" if $DEBUG
    end

    # correcion of coordinate sign and post-decode correction
    def dcd_fixup
      case @dcd['Qc']
      when 1 then :ignore
      when 3 then
        @dcd['La.3'] *= -1 if Numeric === @dcd['La.3']
      when 5 then
        @dcd['La.3'] *= -1 if Numeric === @dcd['La.3']
        @dcd['Lo.4'] *= -1 if Numeric === @dcd['Lo.4']
      when 7 then
        @dcd['Lo.4'] *= -1 if Numeric === @dcd['Lo.4']
      end
      for k in @dcd.keys.grep(/^%/n)
        @dcd.delete(k)
      end
      if @dcd['_sec10'] then
        @dcd['_sec10'] = @dcd['_sec10'].join(',')
      end
      if (51..81).include? @dcd['YY'].to_i
        @dcd['YY'] -= 50
        # knot to m.s-1 conversion
        for k in @dcd.keys.grep(/\Afff@/n)
          case @dcd[k]
          when Numeric
            @dcd[k] = 0.1 * (5.14444 * @dcd[k] + 0.5).floor
          end
        end
      end
    end

  end
  # end of UUAA

  class UUBB < UUAA
    State = UUAA::State.dup
    State[:MMMUU] = :temp5ini 
    Idname = 'a4'
  end

  class UUCC < UUAA
    TPrefix = 't'
    WPrefix = 'w'
    PFactor = 1
    LevelBase = '10'
    def self.atoPPP str
      str.to_i * 0.1
    end
  end

  class UUDD < UUBB
    TPrefix = 't'
    WPrefix = 'w'
    Idname = 'a4'
    PFactor = 1
    LevelBase = '10'
    def self.atoPPP str
      str.to_i * 0.1
    end
  end

  class IIAA < UUAA
    State = UUAA::State.dup
    State[:QLLLL] = :MMMUU 
    State[:MMMUU] = :hhhhi 
    State[:hhhhi] = :temp2ini 
  end

  class TTAA < UUAA
    State = UUAA::State.dup
    State[nil] = :YYGGi 
    State[:YYGGi] = :IIiii 
    State[:IIiii] = :temp2ini 
  end

  class TTBB < UUBB
    State = UUBB::State.dup
    State[nil] = :YYGGi 
    State[:YYGGi] = :IIiii 
    State[:IIiii] = :temp5ini 
  end

  class TTCC < UUCC
    State = UUCC::State.dup
    State[nil] = :YYGGi 
    State[:YYGGi] = :IIiii 
    State[:IIiii] = :temp2ini 
  end

  class TTDD < UUDD
    State = UUDD::State.dup
    State[nil] = :YYGGi 
    State[:YYGGi] = :IIiii 
    State[:IIiii] = :temp5ini 
  end

  module FM32PILOT

    def pilot4leader(group)
      case group
      when /\A77999\z/n then
        return
      when /\A(77|66)/n then
	@z = 'MAXW0'
	@z = @z.succ while @dcd["dd@#{@z}"]
	@dcd["PPP@#{@z}"] = self.class::atoPPP(group[2,3])
	@state = :pilot3
        return
      when /\A(7|6)/n then
	@z = 'MAXW0'
	@z = @z.succ while @dcd["dd@#{@z}"]
	@dcd["HHHH@#{@z}"] = self.class::atoi(group[2,3])
	@state = :pilot3
        return
      when /\A9/n then
        @dcd['%zUnit'], @dcd['%zOfs'] = 300, '0'
      when /\A1/n then
        @dcd['%zUnit'], @dcd['%zOfs'] = 300, '1'
      when /\A8/n then
        @dcd['%zUnit'], @dcd['%zOfs'] = 500, '0'
      end
      @dcd['%tn'] = group[1,1]
      @dcd['%u1'] = group[2,1]
      @dcd['%u2'] = group[3,1]
      @dcd['%u3'] = group[4,1]
      @state = :pilot4h1
    end

    def pilot4follower(group, digit)
      z = Tac.atoi(@dcd.values_at('%zOfs', '%tn', digit).join)
      z = format('%05u', z * @dcd['%zUnit']) if Numeric === z
      @dcd["dd@h#{z}"], @dcd["fff@h#{z}"] = Tac.atoddfff(group)
    end

    PLEVS1 = {
      '92' => [925, 850, 700],
      '85' => [850, 700, 500],
      '70' => [700, 500, 400],
      '50' => [500, 400, 300],
      '40' => [400, 300, 250],
      '30' => [300, 250, 200],
      '25' => [250, 200, 150],
      '20' => [200, 150, 100],
      '15' => [150, 100],
      '10' => [100],
    }
    PLEVS2 = {
      '70' => [70, 50, 30],
      '50' => [50, 30, 20],
      '30' => [30, 20, 10],
      '20' => [20, 10],
      '10' => [10],
    }

    def dcd_main(group)
      istate = @state
      case @state
      when :pilot4ini
        case group
	when /\A00000/n then :ignore
	when /\A[16789]/n then
	  pilot4leader(group)
	when /\A(?:44|55)[123]/n then
	  @dcd['Ind'] = group[0,2]
	  @dcd['%pNum'] = Tac.atoi(group[2,1])
	  @dcd['%pRefs'] = self.class::PLEVS[group[3,2]]
	  @state = :pilot2p1
	when /\A(?:44|55)[\/0](?:\/\/|85)/n then
          :ignore
        when /\A(?:OBSCURED|RAIN)\z/n then
          wputs("ignored (#{group}) in PILOT Sec4")
        when /\ANO\z/n then
          @state = :no
	else
	  eputs("unexpected (#{group}) in PILOT Sec4")
          @state = :err
	end
      when :no
        case group
        when /\A(?:ASCNT|ASENT|ACENT)\z/n then
	  wputs("(NO ASCENT) in PILOT Sec4")
        else
	  eputs("unexpected (NO #{group}) in PILOT Sec4")
        end
        @state = :err
      when :pilot2p1
        z = @dcd['%pRefs'].to_a[0]
	@dcd["dd@p#{z}"], @dcd["fff@p#{z}"] = Tac.atoddfff(group)
	@state = (1 == @dcd['%pNum']) ? :pilot4ini : :pilot2p2
      when :pilot2p2
        z = @dcd['%pRefs'].to_a[1]
	@dcd["dd@p#{z}"], @dcd["fff@p#{z}"] = Tac.atoddfff(group)
	@state = (2 == @dcd['%pNum']) ? :pilot4ini : :pilot2p3
      when :pilot2p3
        z = @dcd['%pRefs'].to_a[2]
	@dcd["dd@p#{z}"], @dcd["fff@p#{z}"] = Tac.atoddfff(group)
	@state = :pilot4ini
      when :pilot3
        case group
	when /^[0123]/n then
	  @dcd["dd@#{@z}"], @dcd["fff@#{@z}"] = Tac.atoddfff(group)
	when /^4/n then
          @dcd['vbvb@' + @z] = Tac.atoi(group[1,2])
          @dcd['vava@' + @z] = Tac.atoi(group[3,3])
	  @state = :pilot4ini
	end
      when :pilot4h1
        pilot4follower(group, '%u1')
	@state = :pilot4h2
      when :pilot4h2
	if /\A[9876]/n === group or (/\A1/n === group and @dcd['%u2'] == '/') then
	  pilot4leader(group)
	else
          pilot4follower(group, '%u2')
	  @state = :pilot4h3
	end
      when :pilot4h3
	if /\A[9876]/n === group or (/\A1/n === group and @dcd['%u3'] == '/') then
	  pilot4leader(group)
	else
          pilot4follower(group, '%u3')
	  @state = :pilot4ini
	end
      when :pilot4p1, :temp6ini
        @dcd['%pPfx'] = 's00' unless @dcd['%pPfx']
        case group
	when /^00/n then
          @z = 'SURF'
	else
	  nn = group[0, 2]
	  if nn < (@dcd['%pPrev'] or '00')
	    @dcd['%pPfx'] = @dcd['%pPfx'].succ
	  end
	  @dcd['%pPrev'] = nn
	  @z = @dcd.values_at('%pPfx', '%pPrev').join
	end
	@dcd["PPP@#{@z}"] = self.class::atoPPP(group[2,3])
	@state = :pilot4pddfff
      when :pilot4pddfff
        @dcd["dd@#{@z}"], @dcd["fff@#{@z}"] = Tac.atoddfff(group)
	@state = :pilot4p1
      end
      puts "@ #{group}: #{istate} -> #{@state}" if $DEBUG
    end

  end

  class PPAA < TTAA
    include FM32PILOT
    PLEVS = PLEVS1
    State = TTAA::State.dup
    State[:IIiii] = :pilot4ini 
  end

  class PPBB < TTBB
    include FM32PILOT
    PLEVS = PLEVS1
    State = TTBB::State.dup
    State[:IIiii] = :pilot4ini 
  end

  class PPCC < TTCC
    include FM32PILOT
    PLEVS = PLEVS2
    State = TTCC::State.dup
    State[:IIiii] = :pilot4ini 
  end

  class PPDD < TTDD
    include FM32PILOT
    PLEVS = PLEVS2
    State = TTDD::State.dup
    State[:IIiii] = :pilot4ini 
  end

  class CLIMAT < self

    def dcd_preempt group
      case group
      when /\A111\z/n then
        if @dcd['P.4'] then
	  wputs("duplicated Sec1 in CLIMAT")
	  @state = :err
	else
	  @state = :climat1
	end
      when /\A222\z/n then @state = :climat2
      when /\A333\z/n then @state = :climat3
      when /\A444\z/n then @state = :climat4
      when /\A555\z/n then @state = :end
      when /\A(?:SEC|SEKSI)\z/n then @state = :hack_SEC
      when /\ANIL\z/n then @state = :nil
      else nil
      end
    end

    def sec1_init
      for k in %w(P0.4 P.4 TTT st.3 eee R1.4 nrnr S1.3 ps.3
      mPmP mTmT mTx mTn meme mRmR mSmS)
        @dcd[k] = '/'
      end
    end

    def dcd_main group, group2
      @state = :IIiii if /\A111\z/n === group2
      case @state
      when :MMJJJ
	if /\ANIL\z/n =~ group2 then
          @dcd['@ID'] = group
	  @state = :nil
	elsif /\A[0-9\/]{5}\z/n =~ group
	  @dcd['MM'] = Tac.atoi(group[0,2])
	  @dcd['JJJ'] = Tac.atoi('2' + group[2,3])
	  @state = :IIiii
	elsif /\A[0-9\/]{3}\z/n =~ group
	  @dcd['MM'] = Tac.atoi(group[0,2])
	  wputs("short (#{group}) for MMJJJ")
	  @state = :IIiii
	elsif /\A(?:Administrator|\/\/END|TEST\.\.)\z/n =~ group
	  wputs("ignored after (#{group})")
	  @state = :err
	elsif /\ALa\z/n =~ group and /\Ainformaci.*n\z/n =~ group2 then
	  wputs("ignored after (#{group} #{group2})")
	  @state = :err
	elsif /\A(?:DE|MOIS)\z/n =~ group
	  wputs("DIAP hack - one line ignored")
	  @state = :hack_DIAP
	elsif /\ATEMP\z/n =~ group and /CSJD\d\d OJAM/n =~ @dcd['AHL']
	  wputs("OJAM hack - word (TEMP) ignored")
	else
	  eputs("unknown (#{group}) at :MMJJJ")
	  @state = :err
	end
      when :IIiii
        @dcd['@ID'] = group
	@state = :climat1
	sec1_init
      when :hack_SEC
	wputs("(SEC) instead of section indicator")
        @state = case group
	  when /^1$/n then
	    sec1_init
	    :climat1
	  when /^2$/n then :climat2
	  when /^3$/n then :climat3
	  when /^4$/n then :climat4
	  else
	    eputs("isolated (SEC) word")
	    :err
	  end
      when :hack_DIAP
        case group
	when /^STOP$/n then @state = :MMJJJ
	end
      when :climat1
        msg = catch(:BadToken) {
	emsg = nil
        case group
	when /^1[0-9\/]{4}/n then
	  @dcd['P0.4'] = Tac.atoPPPP(group[1,4])
	when /^2[0-9\/]{4}/n then
	  @dcd['P.4'] = Tac.atoPPPP(group[1,4])
	when /^3[0-9\/]{7}$/n then
	  @dcd['TTT'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['st.3'] = Tac.atoi(group[5,3])
	when /^4[0-9\/]{8}$/n then
	  @dcd['Tx.3'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['Tn.3'] = Tac.atosi(group[5,1], group[6,3])
	when /^4[0-9\/]{7}$/n then
	  wputs("missing 2nd sn (#{group}) in CLIMAT Sec1")
	  @dcd['Tx.3'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['Tn.3'] = Tac.atosi(group[1,1], group[5,3])
	when /^4[01]\d{3}$/n then
	  unless /^[01]\d{3}/ =~ group2
	    throw(:BadToken, "CLIMAT Sec1 (#{group2})")
	  end
	  @dcd['%prev'] = group
	  @state = :climat1frag
	when /^5[0-9\/]{3}/n then
	  @dcd['eee'] = Tac.atoi(group[1,3])
	when /^6[0-9\/]{6}/n then
	  @dcd['R1.4'] = Tac.atoi(group[1,4])
	  @dcd['nrnr'] = Tac.atoi(group[5,2])
	when /^7[0-9\/]{6}/n then
	  @dcd['S1.3'] = Tac.atoi(group[1,3])
	  @dcd['ps.3'] = Tac.atoi(group[4,3])
	when /^8[0-9\/]{6}/n then
	  @dcd['mPmP'] = Tac.atoi(group[1,2])
	  @dcd['mTmT'] = Tac.atoi(group[3,2])
	  @dcd['mTx'] = Tac.atoi(group[5,1])
	  @dcd['mTn'] = Tac.atoi(group[6,1])
	when /^9[0-9\/]{6}/n then
	  @dcd['meme'] = Tac.atoi(group[1,2])
	  @dcd['mRmR'] = Tac.atoi(group[3,2])
	  @dcd['mSmS'] = Tac.atoi(group[5,2])
	else
	  throw(:BadToken, "CLIMAT Sec1")
	end
	nil
	}
	eputs("unknown (#{group}) in #{msg}") if msg
      when :climat1frag
	prev = @dcd['%prev']
	case join = [prev, group].join
	when /^4[01]\d{3}[01]\d{3}/ then
	  @dcd['Tx.3'] = Tac.atosi(join[1,1], join[2,3])
	  @dcd['Tn.3'] = Tac.atosi(join[5,1], join[6,3])
	else
	  eputs("unknown (#{prev} #{group}) in CLIMAT Sec1")
	end
	@state = :climat1
      when :climat2
        case group
	when /^0[0-9\/]{4}/n then
	  @dcd['YbYb'] = Tac.atoi(group[1,2])
	  @dcd['YcYc'] = Tac.atoi(group[3,2])
	when /^1[0-9\/]{4}/n then
	  @dcd['P0.4/C'] = Tac.atoPPPP(group[1,4])
	when /^2[0-9\/]{4}/n then
	  @dcd['P.4/C'] = Tac.atoPPPP(group[1,4])
	when /^3[0-9\/]{7}/n then
	  @dcd['TTT/C'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['st.3/C'] = Tac.atoi(group[5,3])
	when /^4[0-9\/]{8}/n then
	  @dcd['Tx.3/C'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['Tn.3/C'] = Tac.atosi(group[5,1], group[6,3])
	when /^4[0-9\/]{7}$/n then
	  wputs("missing 2nd sn (#{group}) in CLIMAT Sec2")
	  @dcd['Tx.3'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['Tn.3'] = Tac.atosi(group[1,1], group[5,3])
	when /^5[0-9\/]{3}/n then
	  @dcd['eee/C'] = Tac.atoi(group[1,3])
	when /^6[0-9\/]{6}/n then
	  @dcd['R1.4/C'] = Tac.atoi(group[1,4])
	  @dcd['nrnr/C'] = Tac.atoi(group[5,2])
	when /^7[0-9\/]{3}/n then
	  @dcd['S1.3/C'] = Tac.atoi(group[1,3])
	when /^8[0-9\/]{6}/n then
	  @dcd['yPyP'] = Tac.atoi(group[1,2])
	  @dcd['yTyT'] = Tac.atoi(group[3,2])
	  @dcd['yTx.2'] = Tac.atoi(group[5,2])
	when /^9[0-9\/]{6}/n then
	  @dcd['yeye'] = Tac.atoi(group[1,2])
	  @dcd['yRyR'] = Tac.atoi(group[3,2])
	  @dcd['ySyS'] = Tac.atoi(group[5,2])
	else
	  eputs("unknown (#{group}) in CLIMAT Sec2")
	end
      when :climat3
        case group
	when /^0[0-9\/]{4}/n then
	  @dcd['T25.2'] = Tac.atoi(group[1,2])
	  @dcd['T30.2'] = Tac.atoi(group[3,2])
	when /^1[0-9\/]{4}/n then
	  @dcd['T35.2'] = Tac.atoi(group[1,2])
	  @dcd['T40.2'] = Tac.atoi(group[3,2])
	when /^2[0-9\/]{4}/n then
	  @dcd['Tn0.2'] = Tac.atoi(group[1,2])
	  @dcd['Tx0.2'] = Tac.atoi(group[3,2])
	when /^3[0-9\/]{4}/n then
	  @dcd['R01.2'] = Tac.atoi(group[1,2])
	  @dcd['R05.2'] = Tac.atoi(group[3,2])
	when /^4[0-9\/]{4}/n then
	  @dcd['R10.2'] = Tac.atoi(group[1,2])
	  @dcd['R50.2'] = Tac.atoi(group[3,2])
	when /^5[0-9\/]{4}/n then
	  @dcd['R100.2'] = Tac.atoi(group[1,2])
	  @dcd['R150.2'] = Tac.atoi(group[3,2])
	when /^6[0-9\/]{4}/n then
	  @dcd['s00.2'] = Tac.atoi(group[1,2])
	  @dcd['s01.2'] = Tac.atoi(group[3,2])
	when /^7[0-9\/]{4}/n then
	  @dcd['s10.2'] = Tac.atoi(group[1,2])
	  @dcd['s50.2'] = Tac.atoi(group[3,2])
	when /^8[0-9\/]{6}/n then
	  @dcd['f10.2'] = Tac.atoi(group[1,2])
	  @dcd['f20.2'] = Tac.atoi(group[3,2])
	when /^9[0-9\/]{6}/n then
	  @dcd['V1V1'] = Tac.atoi(group[1,2])
	  @dcd['V2V2'] = Tac.atoi(group[3,2])
	  @dcd['V3V3'] = Tac.atoi(group[5,2])
	else
	  eputs("unknown (#{group}) in CLIMAT Sec3")
	end
      when :climat4
        case group
	when /^0[0-9\/]{6}/n then
	  @dcd['Txd.3'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['yxyx'] = Tac.atoi(group[5,1])
	when /^1[0-9\/]{6}/n then
	  @dcd['Tnd.3'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['ynyn'] = Tac.atoi(group[5,1])
	when /^2[0-9\/]{6}/n then
	  @dcd['Tax.3'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['yax.2'] = Tac.atoi(group[5,1])
	when /^3[0-9\/]{6}/n then
	  @dcd['Tan.3'] = Tac.atosi(group[1,1], group[2,3])
	  @dcd['yan.2'] = Tac.atoi(group[5,1])
	when /^4[0-9\/]{6}/n then
	  @dcd['Rx.4'] = Tac.atoi(group[1,4])
	  @dcd['yryr'] = Tac.atoi(group[5,2])
	when /^5[0-9\/]{6}/n then
	  @dcd['iw'] = Tac.atoi(group[1,1])
	  @dcd['fx.3'] = Tac.atoi(group[2,3])
	  @dcd['yfx.2'] = Tac.atoi(group[5,2])
	when /^6[0-9\/]{4}/n then
	  @dcd['Dts.2'] = Tac.atoi(group[1,2])
	  @dcd['Dgr.2'] = Tac.atoi(group[3,2])
	when /^7[0-9\/]{5}/n then
	  @dcd['iy'] = Tac.atoi(group[1,1])
	  @dcd['GxGx'] = Tac.atoi(group[2,2])
	  @dcd['GnGn'] = Tac.atoi(group[4,2])
	else
	  eputs("unknown (#{group}) in CLIMAT Sec4")
	end
      end
    end

    def dcd_fixup
    end

    def decode
      @state = :MMJJJ
      @hold.size.times {|i|
        group = @hold[i]
        group2 = @hold[i + 1]
        next if dcd_preempt(group)
        dcd_main(group, group2)
      }
      dcd_fixup
    end

  end

  class AMDAR < self

    def heritage
      case @hold.first
      when /^HSSS$/n then @hold[1]
      else @hold.first
      end
    end

    def heritage= val
      @hold.push val if val
    end

    def dcd_preempt group
      case group
      when /\A333\z/n then @state = :amdar_sec3
      when /\ANIL\z/n then @state = :nil
      else nil
      end
    end

    def dcd_main group, group2
      msg = catch(:UNKN) {
      case @state
      when :YYGG
	@dcd['YY'] = Tac.atoi(group[0,2])
	@dcd['GG'] = Tac.atoi(group[2,2])
	@state = :ipipip
      when :ipipip
        @dcd['ip.3'] = group
	@state = :IA_IA
      when :IA_IA
        @dcd['@ID'] = group
	@state = :amdar_sec2
      when :amdar_sec2
        case group
	when /\A[0-9]{4}N\z/ then
	  @dcd['La.4'] = Tac.atoi(group[0,4])
	when /\A[0-9]{4}S\z/ then
	  @dcd['La.4'] = Tac.atosi('1', group[0,4])
	when /\A[0-9]{5}E\z/ then
	  @dcd['Lo.5'] = Tac.atoi(group[0,5])
	when /\A[0-9]{5}W\z/ then
	  @dcd['Lo.5'] = Tac.atosi('1', group[0,5])
	when /\A[0-9]{6}\z/ then
	  @dcd['YY/obs'] = Tac.atoi(group[0,2])
	  @dcd['GG/obs'] = Tac.atoi(group[2,2])
	  @dcd['gg/obs'] = Tac.atoi(group[4,2])
	when /\AF\d{3}\z/ then
	  @dcd['hl.3'] = Tac.atoi(group[1,3])
	when /\AA\d{3}\z/ then
	  @dcd['hl.3'] = Tac.atosi('1', group[1,3])
	when /\APS\d{3}\z/ then
	  @dcd['TA.3'] = Tac.atoi(group[2,3])
	when /\AMS\d{3}\z/ then
	  @dcd['TA.3'] = Tac.atosi('1', group[2,3])
	when /\A\d{3}\z/ then
	  @dcd['UUU'] = Tac.atoi(group[0,3])
	when /\A\/+\z/ then
	  @dcd['Td.3'] = '/'
	when /\APS\d{3}\z/ then
	  @dcd['Td.3'] = Tac.atoi(group[2,3])
	when /\AMS\d{3}\z/ then
	  @dcd['Td.3'] = Tac.atosi('1', group[2,3])
	when /\A\d{3}\/\d{3}\z/ then
	  @dcd['ddd'] = Tac.atoi(group[0,3])
	  @dcd['fff'] = Tac.atoi(group[3,3])
	when /\ATB[\/\d]\z/ then
	  @dcd['Ba'] = Tac.atoi(group[2,3])
	when /\AS[\d\/]{3}\z/ then
	  @dcd['s1'] = Tac.atoi(group[1,1])
	  @dcd['s2'] = Tac.atoi(group[2,1])
	  @dcd['s3'] = Tac.atoi(group[3,1])
	else
	  throw(:UNKN, true)
	end
      when :amdar_sec3
        case group
	when /\AF[\/\d]{3}\z/ then
	  @dcd['hd.3'] = Tac.atoi(group[1,3])
	when /\AVG[\d\/]{3}\z/ then
	  @dcd['fg.3'] = Tac.atoi(group[1,3])
	else
	  throw(:UNKN, true)
	end
      end
      nil
      }
      eputs("uknown (#{group}) at AMDAR #{@state}") if msg
    end

    def dcd_fixup
    end

    def decode
      @state = :YYGG
      @hold.size.times {|i|
        group = @hold[i]
        group2 = @hold[i + 1]
        next if dcd_preempt(group)
        dcd_main(group, group2)
      }
      dcd_fixup
    end

  end

  def self.start ahl, mimj, heritage = nil
    if mimj and const_defined?(mimj)
      klass = const_get(mimj)
    else
      klass = self
    end
    klass.new(ahl, mimj, heritage)
  end

end

class DeTac

  def initialize fnam
    @fnam = fnam
    if fnam == '-' then
      STDIN.binmode
      @s = StringScanner.new(STDIN.read)
    else
      File.open(fnam, 'rb') { |fp| @s = StringScanner.new(fp.read) }
    end
    @hold = nil
    @callback = nil
  end

  def each
    hack_climat = false
    hack_amdar = false
    while true
      # 0xA0 is used in place of space in some reports (ex. HAAB Ethiopia)
      @s.skip(/[\s\xA0]+/n)
      if @s.scan(/=/n) then
        yield(:EQ, @s.matched)
      # preceding \w* removes garbage found in CWAO message
      elsif @s.scan(/\w*([A-Z]{4}[0-9]{0,2} [A-Z]{4} [0-9]{6}(?: [A-Z]{3})?)/n) then
        yield(:AHL, @s[1])
      elsif @s.scan(/(\003|NNNN)/n) then
        yield(:EOF, $1)
      elsif @s.scan(/ZCZC/n) then
        :ignore
      elsif @s.scan(/([A-Z])\1([ABCDVXY])\2/n) then
        hack_climat = false
        hack_amdar = false
        yield(:MiMj, @s.matched)
      elsif @s.scan(/(?:METAR|SPECI|AMDAR)/n) then
        hack_climat = false
        hack_amdar = true
        yield(:MiMj, @s.matched)
      elsif @s.scan(/(?:CLIMAT)/n) then
        hack_climat = true
        hack_amdar = false
        yield(:MiMj, @s.matched)
      elsif @s.scan(/NIL/n) then
        yield(:NIL, @s.matched)
      elsif @s.scan(/NULL/n) then
        yield(:NULL, @s.matched)
      elsif hack_climat and @s.scan(%r!0[ \r\n]+[0-9/]{6}\b|(?:0[0-9/]{6}|9[0-9/]{5})[ \r\n]+[0-9/]\b!n) then
        yield(:WORD, @s.matched.gsub(/ /n, ''))
      elsif hack_climat and @s.scan(%r!6\d{4}X\d\d\b!n) then
        yield(:WORD, @s.matched.gsub(/X/n, '/'))
      elsif hack_climat and @s.scan(%r!2 3 4 5!n) then
        yield(:WORD, '2////')
        yield(:WORD, '3///////')
        yield(:WORD, '4////////')
        yield(:WORD, '5///')
      elsif hack_climat and @s.scan(%r![07][0-9/]{7}|3[0-9]{9}|6[0-9/]{7,8}|[89][0-9/]{8}!n) then
        yield(:XWORD, @s.matched)
      elsif hack_climat and
        @s.scan(%r![012][0-9/]{6}|[34][0-9/]{6,8}|[57][0-9/]{3,6}|6[0-9/]{6}|[89][0-9/]{6,7}!n) then
        yield(:WORD, @s.matched)
      elsif hack_amdar and @s.scan(/(?:[0-9]{5}[EW]|\d{3}\/\d{3})/n) then
        yield(:WORD, @s.matched)
      elsif @s.scan(/[0-9\/]{6} ?[0-9\/]{4}\b/n) then
        x = @s.matched.sub(/ /n, '')
	yield(:WORD, x[0, 5])
	yield(:WORD, x[5, 5])
      elsif @s.scan(/[0-9\/]{5}(222|333|444|555)\b/n) then
        x = @s.matched
	yield(:WORD, x[0, 5])
	yield(:WORD, x[5, 3])
      elsif @s.scan(/[0-3][0-9][012][0-9][0-5][0-9]Z/n) then
        yield(:WORD, @s.matched)
      elsif @s.scan(/[0-9\/]{5,6}/n) then
        yield(:WORD, @s.matched)
      elsif !hack_amdar and @s.scan(/111|222|333|444|555\b/n) then
        yield(:WORD, @s.matched)
      elsif @s.scan(/[0-9] [0-9\/]{4}\b/n) then
        yield(:WORD, @s.matched.sub(/ /n, ''))
      elsif @s.scan(/[0-9\/\&]{5}/n) then
        yield(:WORD, @s.matched.sub(/\&/n, '6'))
      elsif @s.scan(/[12]O[0-9\/]{3}/n) then
        yield(:WORD, @s.matched.sub(/O/n, '0'))
      elsif @s.scan(/A\s/n) then
        :ignore # IRAQ
      elsif @s.scan(/Archive: \S+/n) then
        :ignore
      elsif @s.scan(/(extract|inflat)ing: (\S+)/n) then
        yield(:FNAM, $2)
      elsif @s.scan(/>+/n) then
        :ignore
      elsif @s.scan(/(?:\xC2\xA0|\xC2  )+/n) then
        :ignore
      elsif @s.scan(/[^\s=]+/n) then
        yield(:XWORD, @s.matched)
      elsif @s.eos? then break
      else throw(:BUG, [@s.pos, @s.peek(5)])
      end
    end
  end

  def start(ahl, mimj, heritage)
    return if @hold
    @hold = Tac.start(ahl, mimj)
    @hold.heritage = heritage
    @hold.fnam = @fnam
  end

  def stop
    return unless @hold
    @hold.flush @callback
    @hold = nil
  end

  def decode &callback
    @callback = callback || lambda {|mimj, dcd| puts dcd.to_ltsv }
    @hold = nil
    ahl = mimj = heritage = nil
    each {|ttype, token|
      puts "& #{ttype} #{token.inspect}" if $DEBUG
      case ttype
      when :WORD, :XWORD, :NIL
	start(ahl, mimj, heritage)
        @hold.push(ttype, token)
      when :EQ
	heritage = @hold ? @hold.heritage : nil
        stop
      when :NULL
	start(ahl, mimj, heritage)
        @hold.push(ttype, 'NIL')
	heritage = @hold ? @hold.heritage : nil
        stop
      when :AHL
        stop
        heritage = nil
        ahl = token
	mimj = nil
      when :MiMj
        stop
        mimj = token
	start(ahl, mimj, heritage)
      when :EOF
        stop
	@fnam = nil
      when :FNAM
        stop
	@fnam = token
      else
        throw(:BUG, ["unknown token type", ttype])
      end
    }
    stop
  end

end

if __FILE__ == $0 then
  tval = catch(:BUG) {
    fmt = :to_ltsv
    begin
      for file in ARGV
        case file
        when /^-yaml/ then fmt = :to_yaml
        else
          DeTac.new(file).decode {|mimj, dcd| puts dcd.send(fmt) }
        end
      end
    rescue Errno::EPIPE
    end
    nil
  }
  $stderr.puts tval.inspect if tval
end
