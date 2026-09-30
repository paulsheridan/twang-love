<?xml version="1.0" encoding="UTF-8"?>
<!-- A four-tile terrain fixture for tests/bounce_test.lua: the exact
     property combinations the game has to honour for arrows. It is a
     COLLECTION (one small image per tile) so the fixture carries no
     sheet geometry, and the art is borrowed from the placeholder terrain
     tiles -- only the custom properties matter here, never the pixels.

       id 0  solid              an ordinary wall: arrows embed
       id 1  solid + bounce    a bounce wall: arrows reflect, never stick
       id 2  bounce             a bounce field: reflects arrows but lets
                                bodies through (no "solid")
       id 3  solid + sticky    the legacy spelling, which must keep
                                bouncing arrows for the old spritesheet
                                tileset -->
<tileset version="1.10" tiledversion="1.11.0" name="bounce-fixture" tilewidth="8" tileheight="8" tilecount="4" columns="4">
 <tile id="0">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
  <image source="../maps/tiles/tile_0000.png" width="8" height="8"/>
 </tile>
 <tile id="1">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="bounce" type="bool" value="true"/>
  </properties>
  <image source="../maps/tiles/tile_0001.png" width="8" height="8"/>
 </tile>
 <tile id="2">
  <properties>
   <property name="bounce" type="bool" value="true"/>
  </properties>
  <image source="../maps/tiles/tile_0002.png" width="8" height="8"/>
 </tile>
 <tile id="3">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
  <image source="../maps/tiles/tile_0003.png" width="8" height="8"/>
 </tile>
</tileset>
