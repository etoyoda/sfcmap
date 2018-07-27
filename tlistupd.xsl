<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet 
 xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
 <xsl:output method="text" encoding="UTF-8" />
 <xsl:param name="limit" select='"1999-01-01 00:00:00"' />

<xsl:template match="/">
  <xsl:apply-templates select="//table[@id='MainList']//tr"/>
</xsl:template>

<xsl:template match="tr">
  <xsl:value-of select='concat(string(td[@title="updated"]),
  "&#9;",td/a[@class="JMX"]/@href, "&#10;")'/>
</xsl:template>

</xsl:stylesheet>
