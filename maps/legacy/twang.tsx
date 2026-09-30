<?xml version="1.0" encoding="UTF-8"?>
<!-- twang terrain tileset: 8x8 cells over the untouched spritesheet
     (256x256 = 32 columns x 32 rows, 1024 tiles, firstgid 1 in maps).
     Old 16px cell O maps to sub-tiles at linear ids
     (O//16)*64 + (O%16)*2 + {0, 1, 32, 33} (TL, TR, BL, BR).

     Reserved sprite art (NOT terrain; property records live in
     chars16.tsx): cells 96-103 and 128-170. Cell 135 stays terrain
     (the phase platform; solid + phase on all four subs). Tile-layer
     use of reserved cells is rejected by the loader. Slope tiles and
     the slope property are gone: slope collision was removed. -->
<tileset version="1.10" tiledversion="1.11.0" name="twang" tilewidth="8" tileheight="8" tilecount="1024" columns="32">
 <image source="spritesheet.png" width="256" height="256"/>
 <tile id="2">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="3">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="34">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="35">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="4">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="5">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="36">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="37">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="6">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="7">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="38">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="39">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="8">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="9">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="40">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="41">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="10">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="11">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="42">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="43">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="18">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="19">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="50">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="51">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="20">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="21">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="52">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="53">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="22">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="23">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="54">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="55">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="24">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="25">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="56">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="57">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="64">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="65">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="96">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="97">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="66">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="67">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="98">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="99">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="68">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="69">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="100">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="101">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="70">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="71">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="102">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="103">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="72">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="73">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="104">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="105">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="74">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="75">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="106">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="107">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="80">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="81">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="112">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="113">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="82">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="83">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="114">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="115">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="84">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="85">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="116">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="117">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="86">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="87">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="118">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="119">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="88">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="89">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="120">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="121">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="90">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="91">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="122">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="123">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="128">
  <properties>
   <property name="spring_ext" type="int" value="1"/>
  </properties>
 </tile>
 <tile id="130">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="131">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="162">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="163">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="132">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="133">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="164">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="165">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="134">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="135">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="166">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="167">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="136">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="137">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="168">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="169">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="138">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="139">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="170">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="171">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="140">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="141">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="172">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="173">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="142">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="143">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="174">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="175">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="144">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="145">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="176">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="177">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="146">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="147">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="178">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="179">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="148">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="149">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="180">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="181">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="150">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="151">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="182">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="183">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="152">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="153">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="184">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="185">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="192">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="193">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="224">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="225">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="194">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="195">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="226">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="227">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="196">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="197">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="228">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="229">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="198">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="199">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="230">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="231">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="200">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="201">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="232">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="233">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="202">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="203">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="234">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="235">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="208">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="209">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="240">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="241">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="210">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="211">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="242">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="243">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="212">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="213">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="244">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="245">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="214">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="215">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="246">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="247">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="216">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="217">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="248">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="249">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="222">
  <properties>
   <property name="kind" value="spawn"/>
  </properties>
 </tile>
 <tile id="256">
  <properties>
   <property name="oneway" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="257">
  <properties>
   <property name="oneway" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="288">
  <properties>
   <property name="oneway" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="289">
  <properties>
   <property name="oneway" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="260">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="261">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="292">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="293">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="262">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="263">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="294">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="295">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="264">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="265">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="296">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="297">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="268">
  <properties>
   <property name="kind" value="key"/>
  </properties>
 </tile>
 <tile id="270">
  <properties>
   <property name="kind" value="lock"/>
  </properties>
 </tile>
 <tile id="272">
  <properties>
   <property name="kind" value="door"/>
  </properties>
 </tile>
 <tile id="274">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="275">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="306">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="307">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="276">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="277">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="308">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="309">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="278">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="279">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="310">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="311">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="286">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="arrow_pass" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="287">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="arrow_pass" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="318">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="arrow_pass" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="319">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="arrow_pass" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="322">
  <properties>
   <property name="runnable" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="323">
  <properties>
   <property name="runnable" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="354">
  <properties>
   <property name="runnable" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="355">
  <properties>
   <property name="runnable" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="324">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="325">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="356">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="357">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="326">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="327">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="358">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="359">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="328">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="329">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="360">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="361">
  <properties>
   <property name="solid" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="338">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="339">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="370">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="371">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="340">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="341">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="372">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="373">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="342">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="343">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="374">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="375">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="sticky" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="346">
  <properties>
   <property name="kind" value="switch"/>
  </properties>
 </tile>
 <tile id="526">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="phase" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="527">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="phase" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="558">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="phase" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="559">
  <properties>
   <property name="solid" type="bool" value="true"/>
   <property name="phase" type="bool" value="true"/>
  </properties>
 </tile>
 <tile id="662">
  <properties>
   <property name="kind" value="switch"/>
  </properties>
 </tile>
 <tile id="664">
  <properties>
   <property name="kind" value="exit"/>
  </properties>
 </tile>
</tileset>
