<?xml version="1.0" encoding="UTF-8"?>
<!-- Placeholder art for the big devices (tools/make_standins.py).
     Its own tileset because a Tiled sheet has one cell size: the
     16x16 devices live in chars.tsx. A cell larger than an
     entity's 16px block is drawn standing on the block's bottom
     edge, so the base of each sprite IS the block (rows 16-31,
     cols 8-23) and the room above it is the launch. -->
<tileset version="1.10" tiledversion="1.11.0" name="drafts32" tilewidth="32" tileheight="32" tilecount="2" columns="2">
 <image source="drafts32.png" width="64" height="32"/>
 <tile id="0">
  <properties>
   <property name="kind" value="outdraft"/>
  </properties>
 </tile>
 <tile id="1">
  <properties>
   <property name="kind" value="updraft"/>
  </properties>
 </tile>
</tileset>
