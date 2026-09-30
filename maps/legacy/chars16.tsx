<?xml version="1.0" encoding="UTF-8"?>
<!-- twang sprite tileset: the character/number art the terrain
     tileset reserves. Rectangular copy of spritesheet.png rows
     6-10 (cells 96-175); local id = art label - 96. Maps place
     these at firstgid 1025. Property records only on the object
     kinds whose art moved out of the terrain tileset. -->
<tileset version="1.10" tiledversion="1.11.0" name="twang-sprites" tilewidth="16" tileheight="16" tilecount="80" columns="16">
 <image source="chars16.png" width="256" height="80"/>
 <tile id="41">
  <properties>
   <property name="kind" value="archer"/>
  </properties>
 </tile>
 <tile id="42">
  <properties>
   <property name="kind" value="laser"/>
  </properties>
 </tile>
 <tile id="44">
  <properties>
   <property name="kind" value="melee"/>
  </properties>
 </tile>
 <tile id="47">
  <properties>
   <property name="kind" value="bomber"/>
  </properties>
 </tile>
</tileset>
