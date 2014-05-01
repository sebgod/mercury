<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text" omit-xml-declaration="yes" indent="no" />
<xsl:template match="/module">
	@node <xsl:value-of select="$module"/>
	@chapter <xsl:value-of select="$module"/>
	@example
	<xsl:value-of select="comment" />
	@end example
	
	@node <xsl:value-of select="$module"/> Discriminated union types
	@section Discriminated union types
	<xsl:for-each select="types/du_type">
		@node <xsl:call-template name="node_name" />
    </xsl:for-each>
	<xsl:text>&#xa;&#xa;</xsl:text>
</xsl:template>

<xsl:template name="node_name">
	<xsl:value-of select="translate(@id, '.', '$')" />
</xsl:template>

</xsl:stylesheet>
