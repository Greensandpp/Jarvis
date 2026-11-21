import * as THREE from './three.module.js';
import {buildGuardian as buildRig} from './guardian.js';
// Original detailed mesh: no image characters or remote assets.
export const THEMES = {
 snake: [0x39ffd2,0x1b725d,0x002b28], forest:[0xaaff72,0x216232,0x071f10],
 solar:[0xffe3a0,0x846425,0x241300], inferno:[0xff6739,0x77251c,0x220604],
 apex:[0x49ddff,0x1b4379,0x020c24], mira:[0xd194ff,0x623489,0x180523]
};
export const QUALITY={ultra:{pixelRatio:2,fps:60,particles:220,bloom:true},high:{pixelRatio:1.5,fps:60,particles:180,bloom:true},balanced:{pixelRatio:1.25,fps:30,particles:120,bloom:false},battery:{pixelRatio:1,fps:30,particles:60,bloom:false}};
export function introStage(p){return p<.08?'platform':p<.18?'convergence':p<.3?'skeleton':p<.62?'armour':p<.7?'reactor':p<.76?'eyes':p<.88?'serpent':p<1?'approach':'idle';}
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
export {buildGuardian as buildRig} from "./guardian.js";
export function buildSnake() {
 const count=32,length=5.3,step=length/(count-1),bones=[];
 for(let i=0;i<count;i++){const b=new THREE.Bone();b.name='serpent_'+i;b.position.y=i?step:0;if(i)bones[i-1].add(b);bones.push(b);}
 const rows=160,sides=18,positions=[],indices=[];
 for(let row=0;row<=rows;row++){
  const u=row/rows,r=(.012+.072*Math.sin(Math.min(1,u*1.7)*Math.PI/2))*(1-.2*Math.exp(-(((u-.91)/.08)**2)));
  for(let j=0;j<=sides;j++){
   const a=j/sides*Math.PI*2,scale=1+.045*Math.cos(row*Math.PI+j*Math.PI/2);positions.push(Math.cos(a)*r*scale,u*length,Math.sin(a)*r*scale*.88);
   if(row<rows&&j<sides){const k=row*(sides+1)+j;indices.push(k,k+1,k+sides+1,k+1,k+sides+2,k+sides+1);}
  }
 }
 const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.Float32BufferAttribute(positions,3));geo.setIndex(indices);geo.computeVertexNormals();
 const si=[],sw=[];for(let i=0;i<geo.attributes.position.count;i++){const y=geo.attributes.position.getY(i)/step,k=clamp(Math.floor(y),0,count-2),f=clamp(y-k,0,1);si.push(k,k+1,0,0);sw.push(1-f,f,0,0);}
 geo.setAttribute('skinIndex',new THREE.Uint16BufferAttribute(si,4));geo.setAttribute('skinWeight',new THREE.Float32BufferAttribute(sw,4));
 const material=new THREE.MeshStandardMaterial({color:0x15876c,emissive:0x06533e,emissiveIntensity:.7,metalness:.7,roughness:.26,side:THREE.DoubleSide});
 const mesh=new THREE.SkinnedMesh(geo,material);mesh.add(bones[0]);mesh.bind(new THREE.Skeleton(bones));mesh.frustumCulled=false;
 const head=new THREE.Group();bones[count-1].add(head);
 const eyeMaterial=new THREE.MeshStandardMaterial({color:0xffe5a0,emissive:0xffb32d,emissiveIntensity:3});
 const detail=(parent,scale,pos,mat=material)=>{const m=new THREE.Mesh(new THREE.SphereGeometry(1,18,12),mat);m.scale.set(...scale);m.position.set(...pos);parent.add(m);return m;};
 detail(head,[.135,.185,.09],[0,.075,.005]);detail(head,[.10,.14,.067],[0,.19,.033]);detail(head,[.19,.16,.035],[0,-.055,-.035]);
 for(const sign of [-1,1]){
  detail(head,[.035,.05,.038],[sign*.102,.16,.06]);detail(head,[.023,.028,.017],[sign*.119,.18,.083],eyeMaterial);detail(head,[.028,.055,.027],[sign*.095,.22,.071]);
  for(let i=0;i<5;i++)detail(head,[.022,.038,.012],[sign*(.15-i*.014),-.12+i*.045,-.001]);
 }
 const jaw=new THREE.Group();jaw.position.set(0,.09,.045);head.add(jaw);detail(jaw,[.085,.14,.025],[0,.075,.025]);
 const fangMaterial=new THREE.MeshStandardMaterial({color:0xe4f6e9,roughness:.22});
 for(const sign of [-1,1]){const fang=new THREE.Mesh(new THREE.ConeGeometry(.012,.07,8),fangMaterial);fang.rotation.x=Math.PI/2;fang.position.set(sign*.054,.19,.067);head.add(fang);}
 const tongue=new THREE.Mesh(new THREE.CapsuleGeometry(.005,.11,3,6),eyeMaterial);tongue.position.set(0,.25,.065);jaw.add(tongue);
 return {mesh,bones,head,jaw,material,step};
}
export function animateRig(r,t,state='idle',level=0,intro=1,dt=1) {
 const blend=dt===1?1:1-Math.exp(-dt*9);
 const n=r.named,speaking=state==='speaking',listening=state==='listening',thinking=['thinking','processing','executing'].includes(state);
 n.pelvis.position.y=1.5+Math.sin(t*1.2)*.035+(1-intro)*.8;n.pelvis.rotation.y=Math.sin(t*.32)*.12;
 n.chest.rotation.z=Math.sin(t*.7)*.015;n.chest.scale.y=1+Math.sin(t*2)*.008;
 n.head.rotation.y=Math.sin(t*.73)*.24;n.head.rotation.x=listening?-.14:Math.sin(t*.6)*.05;
 for(const side of ['L','R']){const sign=side==='L'?1:-1;
  n['shoulder'+side].rotation.z=THREE.MathUtils.lerp(n['shoulder'+side].rotation.z,sign*(.1+Math.sin(t*.9)*.06+(listening?.55:thinking?.8:speaking?.16+Math.sin(t*2.2)*.14:0)),blend);
  n['elbow'+side].rotation.x=THREE.MathUtils.lerp(n['elbow'+side].rotation.x,-.12-(thinking?1.1:speaking?.32+Math.sin(t*1.8)*.2:Math.sin(t*.7)*.12),blend);
  n['wrist'+side].rotation.y=Math.sin(t*1.3)*.2;
  for(let f=0;f<5;f++){const curl=.18+(Math.sin(t*1.4+f*.3)+1)*.23;n['finger'+side+f].rotation.x=curl;n['tip'+side+f].rotation.x=curl*.7;}
 }
 n.jaw.rotation.x=THREE.MathUtils.lerp(n.jaw.rotation.x,speaking?.08+Math.abs(Math.sin(t*14))*(.12+level*.3):0,blend);
 n.eyeL.rotation.y=n.eyeR.rotation.y=Math.sin(t*.73)*.15;
 r.armour.forEach((m,i)=>{const k=clamp((intro-.2-i/r.armour.length*.22)/.45,0,1);m.visible=intro>.15 && intro<.995 && (!m.userData.bone.name.startsWith('eye') || intro>.7);m.position.copy(m.userData.rest).addScaledVector(new THREE.Vector3(Math.sin(i*7),.5,Math.cos(i*7)),(1-k)*1.5);});
 r.glow.emissiveIntensity=intro<.65?0:1.6+Math.sin(t*3)*.3+(speaking?level:0);
 r.mesh.geometry.setDrawRange(0,intro>=.995?Infinity:0);r.mesh.visible=intro>.12;
 r.mesh.updateMatrixWorld(true);
}
export function animateSnake(s,t,intro=1) {
 // Procedural inverse kinematics: the independently rigged serpent follows
 // a spatial helix around the humanoid, with a travelling slither wave.
 const count=s.bones.length,up=new THREE.Vector3(0,1,0);
 const path=(i)=>{const u=i/(count-1),a=t*.55+u*Math.PI*2;
  const radius=.82+Math.sin(t*1.1-u*7)*.055;
  const p=new THREE.Vector3(Math.cos(a)*radius,.4+u*2.35+Math.sin(t*1.4-u*6)*.08,Math.sin(a)*radius);
  return p.lerp(new THREE.Vector3(.72+Math.sin(t*.6)*.04,2.8+Math.sin(t)*.07,.02),THREE.MathUtils.smoothstep(u,.84,1));
 };
 s.mesh.scale.setScalar(1);s.mesh.updateMatrixWorld(true);
 for(let i=0;i<count;i++) {
  const b=s.bones[i],p=path(i),next=path(i+1);
  const world=new THREE.Quaternion().setFromUnitVectors(up,next.sub(p).normalize());
  if(i===0){b.position.copy(p);b.quaternion.copy(world);}
  else {b.position.copy(b.parent.worldToLocal(p));
    const parent=b.parent.getWorldQuaternion(new THREE.Quaternion());
    b.quaternion.copy(parent.invert().multiply(world));
  }
  b.updateWorldMatrix(false,false);
 }
 s.material.transparent=intro<1;s.material.opacity=clamp((intro-.72)/.16,0,1);
 s.head.rotation.y=Math.sin(t*1.6)*.5;s.jaw.rotation.x=.15+(Math.sin(t*2)+1)*.23;
 s.mesh.visible=intro>.72 && Math.sin(t*.12)>-.93;s.mesh.updateMatrixWorld(true);
}
export function startScene() {
 const report=(v)=>window.HologramBridge?.postMessage(JSON.stringify(v));
 let renderer;try{renderer=new THREE.WebGLRenderer({antialias:true,alpha:false,powerPreference:'high-performance'});}catch(e){report({type:'error',message:'WebGL unavailable'});return;}
 document.body.appendChild(renderer.domElement);renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));renderer.setClearColor(0x01070b);
 const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(36,1,.1,60);scene.fog=new THREE.FogExp2(0x01070b,.045);
 renderer.info.autoReset=false;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.15;
 const studio=new THREE.Scene();studio.background=new THREE.Color(0x263545);
 for(const [x,y,z,w,h,c] of [[-3,3,0,3,5,0x7ddfff],[3,2,1,2,4,0xffe0a0],[0,5,-3,5,2,0xffffff]]){
  const panel=new THREE.Mesh(new THREE.PlaneGeometry(w,h),new THREE.MeshBasicMaterial({color:c,side:THREE.DoubleSide}));panel.position.set(x,y,z);panel.lookAt(0,1.5,0);studio.add(panel);
 }
 let environment;function restoreEnvironment(){environment?.dispose();const pmrem=new THREE.PMREMGenerator(renderer);environment=pmrem.fromScene(studio,.08);scene.environment=environment.texture;pmrem.dispose();}restoreEnvironment();
 const ambient=new THREE.HemisphereLight(0xb8eaff,0x142029,1.8);scene.add(ambient);
 const key=new THREE.PointLight(0x49ddff,90,12),rim=new THREE.PointLight(0x8056ff,65,12);key.position.set(2,4,3);rim.position.set(-2,3,-2);scene.add(key,rim);
 const rig=buildRig(),snake=buildSnake();scene.add(rig.mesh,snake.mesh);
 const scaffold=new THREE.SkeletonHelper(rig.mesh);scaffold.material.color.setHex(0x69f5ff);scaffold.material.transparent=true;scene.add(scaffold);
 const target=new THREE.WebGLRenderTarget(1,1,{depthBuffer:true});
 const postScene=new THREE.Scene(),postCamera=new THREE.OrthographicCamera(-1,1,1,-1,0,1);
 const postMaterial=new THREE.ShaderMaterial({uniforms:{image:{value:target.texture},texel:{value:new THREE.Vector2(1,1)}},vertexShader:'varying vec2 uv0;void main(){uv0=uv;gl_Position=vec4(position.xy,0.,1.);}',fragmentShader:`uniform sampler2D image;uniform vec2 texel;varying vec2 uv0;void main(){vec3 base=texture2D(image,uv0).rgb;vec3 glow=vec3(0.);for(int i=-2;i<=2;i++){for(int j=-2;j<=2;j++){vec3 c=texture2D(image,uv0+vec2(float(i),float(j))*texel*3.).rgb;glow+=max(c-vec3(.72),vec3(0.));}}gl_FragColor=vec4(base+glow*.035,1.);}`});
 postScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2,2),postMaterial));
 const platform=new THREE.Mesh(new THREE.CylinderGeometry(1.3,1.4,.09,64),rig.metal);platform.position.y=.04;scene.add(platform);
 const ring=new THREE.Mesh(new THREE.TorusGeometry(1.35,.016,8,96),rig.glow);ring.rotation.x=Math.PI/2;ring.position.y=.1;scene.add(ring);
 const particlesGeo=new THREE.BufferGeometry(),particles=[];for(let i=0;i<220;i++)particles.push(Math.sin(i*93)*3,(i%40)/9,Math.cos(i*77)*3);particlesGeo.setAttribute('position',new THREE.Float32BufferAttribute(particles,3));
 const particleMaterial=new THREE.PointsMaterial({color:0x49ddff,size:.018,transparent:true,opacity:.7});const points=new THREE.Points(particlesGeo,particleMaterial);scene.add(points);
 const trailGeo=new THREE.BufferGeometry(),trailPos=new Float32Array(72*3);trailGeo.setAttribute('position',new THREE.BufferAttribute(trailPos,3));const trail=new THREE.Line(trailGeo,new THREE.LineBasicMaterial({color:0x49ddff,transparent:true,opacity:.5}));scene.add(trail);
 const environments={};
 for(const name of Object.keys(THEMES)) {
  const group=new THREE.Group();environments[name]=group;scene.add(group);
  for(let i=0;i<12;i++) {
   let geo;
   if(name==='mira')geo=new THREE.OctahedronGeometry(.16+(i%3)*.08);
   else if(name==='forest')geo=new THREE.CylinderGeometry(.015,.07,1.2+(i%4)*.3,5);
   else if(name==='solar')geo=new THREE.TorusGeometry(.5+i*.06,.008,5,48);
   else if(name==='apex')geo=new THREE.RingGeometry(.16,.18,6);
   else if(name==='inferno')geo=new THREE.ConeGeometry(.045,.7,3);
   else geo=new THREE.IcosahedronGeometry(.035);
   const material=new THREE.MeshStandardMaterial({color:THEMES[name][0],emissive:THEMES[name][0],emissiveIntensity:1.2,metalness:.5,roughness:.25,transparent:true,opacity:.45,side:THREE.DoubleSide});
   const m=new THREE.Mesh(geo,material);
   if(name==='solar')m.position.set(0,1.8,0);
   else m.position.set(Math.sin(i*2.4)*2,.2+(i%5)*.58,Math.cos(i*2.4)*1.8-1);
   m.position.z=-1.5-Math.abs(m.position.z);m.scale.setScalar(.65);
   m.rotation.set(i*.2,i*.3,i*.4);group.add(m);
  }
 }
 let quality='balanced',contextLost=false,introProgress=0;
 let state='idle',theme='snake',introStart=performance.now(),introEnabled=true,reduced=false,paused=false,level=0,done=false,elapsed=0,last=0,fps=60,frames=0,windowStart=0;
 let yaw=0,pitch=.06,distance=6.7,drag=false,startX=0,startY=0,lastInput=0,pointers=new Map(),pinch=0;
 function applyTheme(name){theme=THEMES[name]?name:'snake';for(const [key,env] of Object.entries(environments))env.visible=key===theme;const [a,b,c]=THEMES[theme];rig.glow.color.setHex(a);rig.glow.emissive.setHex(a);key.color.setHex(a);rim.color.setHex(b);snake.material.color.setHex(b);snake.material.emissive.setHex(a);snake.material.emissiveIntensity=.2;particleMaterial.color.setHex(a);trail.material.color.setHex(a);scene.fog.color.setHex(0x01070b);renderer.setClearColor(0x01070b);}
 window.jarvisScene={update(v){if(v.state)state=v.state;if(v.quality&&QUALITY[v.quality]&&v.quality!==quality){quality=v.quality;renderer.setPixelRatio(Math.min(devicePixelRatio,QUALITY[quality].pixelRatio));particlesGeo.setDrawRange(0,QUALITY[quality].particles);resize();}if(v.theme)applyTheme(v.theme);level=clamp(Number(v.level)||0,0,1);reduced=!!v.reduceMotion;if(v.intro===false){introEnabled=false;done=true;}},skipIntro(){introEnabled=false;done=true;report({type:'introFinished'});},pause(v){paused=!!v;},snapshot(){return{engine:'Three.js r180 WebGL',state,theme,bones:rig.bones.length,snakeBones:snake.bones.length,intro:done?'done':'running',introStage:introStage(introProgress),quality,contextLost,armourPlates:rig.armour.length,geometryBytes:rig.mesh.geometry.attributes.position.array.byteLength,materials:rig.materials.length,humanoidHead:rig.named.head.getWorldPosition(new THREE.Vector3()).toArray(),snakeHead:snake.head.getWorldPosition(new THREE.Vector3()).toArray(),fps,drawCalls:renderer.info.render.calls,triangles:renderer.info.render.triangles};}};
 const canvas=renderer.domElement;
 canvas.addEventListener('pointerdown',e=>{pointers.set(e.pointerId,[e.clientX,e.clientY]);if(pointers.size===1){drag=false;startX=e.clientX;startY=e.clientY;}if(pointers.size===2){const a=[...pointers.values()];pinch=Math.hypot(a[0][0]-a[1][0],a[0][1]-a[1][1]);}canvas.setPointerCapture(e.pointerId);lastInput=performance.now();});
 canvas.addEventListener('pointermove',e=>{if(!pointers.has(e.pointerId))return;const prev=pointers.get(e.pointerId);pointers.set(e.pointerId,[e.clientX,e.clientY]);if(pointers.size===2){const a=[...pointers.values()],d=Math.hypot(a[0][0]-a[1][0],a[0][1]-a[1][1]);distance=clamp(distance+(pinch-d)*.012,5,11);pinch=d;drag=true;}else{if(Math.hypot(e.clientX-startX,e.clientY-startY)>8)drag=true;if(drag){yaw+=(e.clientX-prev[0])*.006;pitch=clamp(pitch+(e.clientY-prev[1])*.004,-.25,.6);}}lastInput=performance.now();});
 canvas.addEventListener('pointerup',e=>{pointers.delete(e.pointerId);if(!drag)report({type:'tap'});lastInput=performance.now();});canvas.addEventListener('pointercancel',e=>pointers.delete(e.pointerId));
 canvas.addEventListener('wheel',e=>{e.preventDefault();distance=clamp(distance+e.deltaY*.003,5,11);lastInput=performance.now();},{passive:false});
 function resize(){const w=innerWidth,h=innerHeight;renderer.setSize(w,h);const size=renderer.getDrawingBufferSize(new THREE.Vector2());target.setSize(size.x,size.y);postMaterial.uniforms.texel.value.set(1/size.x,1/size.y);camera.aspect=w/h;camera.updateProjectionMatrix();}addEventListener('resize',resize);resize();particlesGeo.setDrawRange(0,QUALITY[quality].particles);renderer.setPixelRatio(Math.min(devicePixelRatio,QUALITY[quality].pixelRatio));resize();applyTheme(theme);
 function frame(now){requestAnimationFrame(frame);if(paused||document.hidden||contextLost){last=now;return;}if(now-last<1000/QUALITY[quality].fps-1)return;const dt=Math.min((now-last)/1000,.05);last=now;if(!reduced)elapsed+=dt;const t=elapsed;
  let intro=introEnabled&&!reduced?clamp((now-introStart)/6500,0,1):1;introProgress=intro;scaffold.visible=intro>.16&&intro<.65;scaffold.material.opacity=1-THREE.MathUtils.smoothstep(intro,.35,.65);if(intro===1&&!done){done=true;report({type:'introFinished'});}
  // Particle convergence is geometry motion, not a background crossfade.
  if(intro<.35){const p=particlesGeo.attributes.position;const collapse=1-Math.sin(clamp(intro/.3,0,1)*Math.PI)*.92;for(let i=0;i<p.count;i++){p.setXYZ(i,particles[i*3]*collapse,1.6+(particles[i*3+1]-1.6)*collapse,particles[i*3+2]*collapse);}p.needsUpdate=true;}
  animateRig(rig,t,state,level,intro,dt);animateSnake(snake,t,intro);
  if(!reduced){points.rotation.y=t*.035;ring.rotation.z=t*.1;environments[theme].children.forEach((m,i)=>{m.rotation.y=t*(theme==='inferno'?2:.2)+i*.2;m.rotation.z=Math.sin(t*.4+i)*.3;});}
  if(now-lastInput>2800&&!pointers.size){yaw*=.97;pitch+=(.06-pitch)*.03;distance+=(6.7-distance)*.03;}
  const d=distance+(1-intro)*2;camera.position.set(Math.sin(yaw)*d,2+pitch*d,Math.cos(yaw)*d);camera.lookAt(0,1.7,0);
  const p=new THREE.Vector3();snake.head.getWorldPosition(p);if(!reduced){trailPos.copyWithin(3,0,trailPos.length-3);trailPos.set([p.x,p.y,p.z],0);trailGeo.attributes.position.needsUpdate=true;trailGeo.computeBoundingSphere();}trail.visible=snake.mesh.visible;
  renderer.info.reset();if(QUALITY[quality].bloom){renderer.setRenderTarget(target);renderer.render(scene,camera);renderer.setRenderTarget(null);renderer.render(postScene,postCamera);}else renderer.render(scene,camera);frames++;if(now-windowStart>2000){fps=frames*1000/(now-windowStart);frames=0;windowStart=now;if(fps<32)renderer.setPixelRatio(1);report({type:'metrics',...window.jarvisScene.snapshot()});}
 }
 requestAnimationFrame(frame);report({type:'ready'});
 canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();contextLost=true;report({type:'contextLost'});});
 canvas.addEventListener('webglcontextrestored',()=>{contextLost=false;last=performance.now();restoreEnvironment();resize();report({type:'ready'});});
}
if(typeof window!=='undefined'&&!window.__HOLOGRAM_TEST__)startScene();
