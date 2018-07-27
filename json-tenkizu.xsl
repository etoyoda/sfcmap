<?xml version="1.0" encoding="UTF-8" ?>
<stylesheet version="1.0" xmlns="http://www.w3.org/1999/XSL/Transform"
 xmlns:j="http://xml.kishou.go.jp/jmaxml1/" 
 xmlns:b="http://xml.kishou.go.jp/jmaxml1/body/meteorology1/"
 xmlns:ib="http://xml.kishou.go.jp/jmaxml1/informationBasis1/"
 xmlns:eb="http://xml.kishou.go.jp/jmaxml1/elementBasis1/"
 xmlns:xlink="http://www.w3.org/1999/xlink" >

<output method="text" encoding="UTF-8"/>

<!-- メインテンプレート -->

<template match="/"><!--
-->{
 "type": "FeatureCollection",
 "x-timestamp": "<value-of select="j:Report/ib:Head/ib:ReportDateTime"/>",
 "x-validtime": "<value-of select="j:Report/ib:Head/ib:TargetDateTime"/>",
 "features": [<for-each
 select="j:Report/b:Body/b:MeteorologicalInfos/b:MeteorologicalInfo/b:Item
 [.//b:CenterPart
 or .//b:CoordinatePart
 or .//b:Area
 or .//b:IsobarPart]"
 >
 <if test="position() &gt; 1">,&#10; </if>
 <apply-templates select="."/>
 </for-each>]
}
</template>
<!-- メインテンプレート終わり -->

<template match="b:Item">{
  "type": "Feature",
  "geometry": <call-template name="geometry"/>,
  "properties": <call-template name="properties"/>
 }<!--
--></template>

<template name="geometry">
<choose>
<when test=".//eb:Line">{
   "type": "LineString",
   "coordinates": [<call-template name="iso2line">
   <with-param name="iso"
   select=".//eb:Line" />
   </call-template>]
  }</when>
<when test=".//b:CenterPart">{
   "type": "Point",
   "coordinates": <call-template name="iso2point">
   <with-param name="iso"
   select=".//b:CenterPart/eb:Coordinate" />
   </call-template>
  }</when>
<when test=".//b:Area/eb:Polygon">{
   "type": "Polygon",
   "coordinates": [[<call-template name="iso2line">
   <with-param name="iso"
   select=".//b:Area/eb:Polygon" />
   </call-template>]]
  }</when>
<when test=".//b:Area/b:Code">{
   "type": "Point",
   "coordinates": <call-template name="AreaMarineA">
   <with-param name="code"
   select=".//b:Area/b:Code" />
   </call-template>
  }</when>
<when test=".//b:Area[string-length(eb:Coordinate) &lt; 15]">{
   "type": "Point",
   "coordinates": <call-template name="iso2point">
   <with-param name="iso"
   select=".//b:Area/eb:Coordinate" />
   </call-template>
  }</when>
<when test=".//b:Area">{
   "type": "LineString",
   "coordinates": [<call-template name="iso2line">
   <with-param name="iso"
   select=".//b:Area/eb:Coordinate" />
   </call-template>]
  }</when>
<otherwise>
 <message terminate="no">unknwn feature type <value-of select="."/></message>
 { "type": "point", "coordinates": [90, 0] }
</otherwise>
</choose>
</template>

<template name="AreaMarineA">
<param name="code"/>
<choose>
<when test="$code = 9010">[135, 40]</when>
<when test="$code = 9011">[137, 40]</when>
<when test="$code = 9012">[132, 37]</when>
<when test="$code = 9013">[131, 40]</when>
<when test="$code = 9014">[137, 43]</when>
<when test="$code = 9015">[135, 40]</when>
<when test="$code = 9020">[120, 39]</when>
<when test="$code = 9030">[124, 36]</when>
<when test="$code = 9040">[125, 29]</when>
<when test="$code = 9050">[149, 53]</when>
<otherwise>
 <message terminate="no">unknwn area code <value-of select="$code"/></message>
 <text>[90.0, 0.0]</text>
</otherwise>
</choose>
</template>

<template name="WxFeatureType">
<param name="jtype"/>
<choose>
<when test="$jtype = '台風'">T</when>
<when test="$jtype = '熱帯低気圧'">TD</when>
<when test="$jtype = '低圧部'">LA</when>
<when test="$jtype = '低気圧'">L</when>
<when test="$jtype = '高気圧'">H</when>
<when test="$jtype = '等圧線'">ISOBAR</when>
<when test="$jtype = '寒冷前線'">CF</when>
<when test="$jtype = '温暖前線'">WF</when>
<when test="$jtype = '閉塞前線'">OF</when>
<when test="$jtype = '停滞前線'">SF</when>
<when test="contains($jtype, '風')">GW</when>
<when test="contains($jtype, '霧')">FOG</when>
<when test="contains($jtype, '海氷')">SEAICE</when>
<when test="contains($jtype, '船体着氷')">ICING</when>
<otherwise>
 <message terminate="no">unknwn feature type <value-of select="$jtype"/></message>
 <value-of select="concat('unknown:', $jtype)"/>
</otherwise>
</choose>
</template>

<template name="iso2point">
<param name="iso"/>
<variable name="pat"><value-of select="translate(
 $iso, '123456789', '000000000')"/></variable>
<choose>
<when test="$pat = '+00.00+000.00/'">
 <value-of select="concat(
  '[', number(substring($iso,8,6)), ', ', number(substring($iso,2,5)), ']')"/>
</when>
<when test="$pat = '+00.00-000.00/'">
 <value-of select="concat(
  '[', 360-number(substring($iso,8,6)), ', ', number(substring($iso,2,5)), ']')"/>
</when>
<when test="$pat = '-00.00+000.00/'">
 <value-of select="concat(
  '[', number(substring($iso,8,6)), ', ', -number(substring($iso,2,5)), ']')"/>
</when>
<when test="$pat = '-00.00-000.00/'">
 <value-of select="concat(
  '[', 360-number(substring($iso,8,6)), ', ', -number(substring($iso,2,5)), ']')"/>
</when>
<when test="$pat = '+00.0+000.0/'">
 <value-of select="concat(
  '[', number(substring($iso,7,5)), ', ', number(substring($iso,2,4)), ']')"/>
</when>
<when test="$pat = '+00.0-000.0/'">
 <value-of select="concat(
  '[', 360-number(substring($iso,7,5)), ', ', number(substring($iso,2,4)), ']')"/>
</when>
<when test="$pat = '+00+000/'">
 <value-of select="concat(
  '[', number(substring($iso,5,3)), ', ', number(substring($iso,2,2)), ']')"/>
</when>
<otherwise>
 <message terminate="no"><value-of select="concat(
 'bad coord (', $iso, ')')"/></message>
 <text>[90, 0]</text>
</otherwise>
</choose>
</template>

<template name="iso2line">
  <param name="iso"/>
  <call-template name="iso2point">
    <with-param name="iso" select="concat(substring-before($iso,'/'),'/')"/>
  </call-template>
  <choose>
  <when test="(string-length($iso) &lt; 300) and 
  contains(substring-after($iso,'/'),'/')">
    <text>,
    </text>
    <call-template name="iso2line">
      <with-param name="iso" select="substring-after($iso,'/')"/>
    </call-template>
  </when>
  <when test="contains(substring-after(substring-after($iso,'/'),'/'),'/')">
    <text>,
    </text>
    <call-template name="iso2line">
      <with-param name="iso" select="substring-after(substring-after($iso,'/'),'/')"/>
    </call-template>
  </when>
  </choose>
</template>

<template name="properties">{<!--
--><choose>
<when test=".//b:CenterPart">
   "pressure": <value-of select=".//eb:Pressure"/>,<!--
--></when>
<when test=".//b:IsobarPart">
   "pressure": <value-of select=".//eb:Pressure"/>,<!--
--></when>
<when test=".//b:WindPart">
   "winddir/deg": <value-of select=".//eb:WindDegree"/>,
   "windspeed/knot": <value-of select=".//eb:WindSpeed"/>,<!--
--></when>
<otherwise></otherwise>
</choose>
   "x-type": "<call-template name="WxFeatureType">
   <with-param name="jtype" select="concat(b:Kind/b:Property/b:Type, b:Kind/b:Name)" />
   </call-template>"
  }</template>

</stylesheet>
