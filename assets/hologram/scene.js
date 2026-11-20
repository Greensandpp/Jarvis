import * as THREE from './three.module.js';
// Original procedural prototype. No character images or remote assets.
export const THEMES = {
 snake: [0x39ffd2,0x1b725d,0x002b28], forest:[0xaaff72,0x216232,0x071f10],
 solar:[0xffe3a0,0x846425,0x241300], inferno:[0xff6739,0x77251c,0x220604],
 apex:[0x49ddff,0x1b4379,0x020c24], mira:[0xd194ff,0x623489,0x180523]
};
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
export function buildRig() {
 const root=new THREE.Bone(); root.name='pelvis'; root.position.y=1.5;
 const bones=[root], named={pelvis:root}, armour=[];
 const skin={position:[],normal:[],skinIndex:[],skinWeight:[]};
 const metal=new THREE.MeshStandardMaterial({color:0x4c8795,emissive:0x0b2832,emissiveIntensity:.7,metalness:.35,roughness:.32});
 const glow=new THREE.MeshStandardMaterial({color:0x49ddff,emissive:0x49ddff,emissiveIntensity:2,metalness:.3,roughness:.22});
 const add=(name,parent,pos)=>{const b=new THREE.Bone();b.name=name;b.position.set(...pos);parent.add(b);bones.push(b);named[name]=b;return b;};
 const chest=add('chest',root,[0,.52,0]);
 const head=add('head',chest,[0,.72,0]);
 const jaw=add('jaw',head,[0,-.16,.12]);
 const eyeL=add('eyeL',head,[-.105,.03,.22]),eyeR=add('eyeR',head,[.105,.03,.22]);
 for(const [sign,side] of [[-1,'L'],[1,'R']]) {
  const shoulder=add('shoulder'+side,chest,[sign*.43,.34,0]);
  const elbow=add('elbow'+side,shoulder,[sign*.2,-.53,0]);
  const wrist=add('wrist'+side,elbow,[sign*.05,-.45,0]);
  for(let f=0;f<5;f++){const finger=add('finger'+side+f,wrist,[(f-2)*.046,-.12,.03]);add('tip'+side+f,finger,[0,-.11,0]);}
  const hip=add('hip'+side,root,[sign*.2,-.12,0]);
  const knee=add('knee'+side,hip,[0,-.68,.015]);add('ankle'+side,knee,[0,-.65,.06]);
 }
 root.updateMatrixWorld(true);
 function part(bone,size,offset=[0,0,0],emissive=false) {
  // Rigid armour attached to each skeleton bone; assembly offset is animated.
  const geo=new THREE.BoxGeometry(...size,1,1,1);
  const m=new THREE.Mesh(geo,emissive?glow:metal);m.position.set(...offset);bone.add(m);
  m.userData.rest=m.position.clone();armour.push(m);
  // One genuine skinned under-mesh with per-bone bind weights.
  const g=geo.toNonIndexed();g.scale(.91,.91,.91);g.translate(...offset);g.applyMatrix4(bone.matrixWorld);
  const idx=bones.indexOf(bone),p=g.attributes.position,n=g.attributes.normal;
  for(let i=0;i<p.count;i++){skin.position.push(p.getX(i),p.getY(i),p.getZ(i));skin.normal.push(n.getX(i),n.getY(i),n.getZ(i));skin.skinIndex.push(idx,0,0,0);skin.skinWeight.push(1,0,0,0);}
  return m;
 }
 part(root,[.48,.3,.3]);part(chest,[.72,.55,.36],[0,.18,0]);
 part(head,[.36,.4,.36]);part(jaw,[.28,.08,.16]);
 part(eyeL,[.075,.028,.035],[0,0,0],true);part(eyeR,[.075,.028,.035],[0,0,0],true);
 const reactor=part(chest,[.15,.15,.07],[0,.2,.22],true);reactor.rotation.z=Math.PI/4;
 for(const side of ['L','R']){
  part(named['shoulder'+side],[.26,.48,.28],[0,-.18,0]);part(named['elbow'+side],[.21,.4,.23],[0,-.18,0]);part(named['wrist'+side],[.22,.19,.15],[0,-.05,0]);
  part(named['hip'+side],[.28,.6,.3],[0,-.29,0]);part(named['knee'+side],[.24,.57,.24],[0,-.28,0]);part(named['ankle'+side],[.27,.16,.43],[0,-.02,.07]);
  for(let f=0;f<5;f++){part(named['finger'+side+f],[.034,.1,.04],[0,-.045,0]);part(named['tip'+side+f],[.03,.09,.035],[0,-.04,0]);}
 }
 const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(skin.position,3));g.setAttribute('normal',new THREE.Float32BufferAttribute(skin.normal,3));g.setAttribute('skinIndex',new THREE.Uint16BufferAttribute(skin.skinIndex,4));g.setAttribute('skinWeight',new THREE.Float32BufferAttribute(skin.skinWeight,4));
 const mesh=new THREE.SkinnedMesh(g,new THREE.MeshStandardMaterial({color:0x081820,roughness:.7}));mesh.add(root);mesh.bind(new THREE.Skeleton(bones));mesh.frustumCulled=false;
 return {mesh,bones,named,armour,metal,glow,reactor};
}
export function buildSnake() {
 const count=32,length=5.3,step=length/(count-1),bones=[];
 for(let i=0;i<count;i++){const b=new THREE.Bone();b.name='serpent_'+i;b.position.y=i?step:0;if(i)bones[i-1].add(b);bones.push(b);}
 const geo=new THREE.CylinderGeometry(.08,.025,length,10,124,true);geo.translate(0,length/2,0);
 const si=[],sw=[];for(let i=0;i<geo.attributes.position.count;i++){const y=geo.attributes.position.getY(i)/step,k=clamp(Math.floor(y),0,count-2),f=clamp(y-k,0,1);si.push(k,k+1,0,0);sw.push(1-f,f,0,0);}
 geo.setAttribute('skinIndex',new THREE.Uint16BufferAttribute(si,4));geo.setAttribute('skinWeight',new THREE.Float32BufferAttribute(sw,4));
 const material=new THREE.MeshStandardMaterial({color:0x15876c,emissive:0x06533e,emissiveIntensity:.7,metalness:.7,roughness:.26,side:THREE.DoubleSide});
 const mesh=new THREE.SkinnedMesh(geo,material);mesh.add(bones[0]);mesh.bind(new THREE.Skeleton(bones));mesh.frustumCulled=false;
 const head=new THREE.Mesh(new THREE.SphereGeometry(.14,16,12),material);head.scale.set(1,1.5,.8);bones[count-1].add(head);
 const jaw=new THREE.Group();jaw.position.set(0,.02,.08);head.add(jaw);const lower=new THREE.Mesh(new THREE.BoxGeometry(.16,.12,.07),material);lower.position.y=.06;jaw.add(lower);
 return {mesh,bones,head,jaw,material,step};
}
export function animateRig(r,t,state='idle',level=0,intro=1,dt=1) {
 const blend=dt===1?1:1-Math.exp(-dt*9);
 const n=r.named,speaking=state==='speaking',listening=state==='listening',thinking=['thinking','processing','executing'].includes(state);
 n.pelvis.position.y=1.5+Math.sin(t*1.2)*.035+(1-intro)*.8;n.pelvis.rotation.y=Math.sin(t*.32)*.12;
 n.chest.rotation.z=Math.sin(t*.7)*.015;n.chest.scale.y=1+Math.sin(t*2)*.008;
 n.head.rotation.y=Math.sin(t*.73)*.24;n.head.rotation.x=listening?-.14:Math.sin(t*.6)*.05;
 for(const side of ['L','R']){const sign=side==='L'?1:-1;
  n['shoulder'+side].rotation.z=THREE.MathUtils.lerp(n['shoulder'+side].rotation.z,sign*(.1+Math.sin(t*.9)*.06+(listening?.55:thinking?.8:0)),blend);
  n['elbow'+side].rotation.x=THREE.MathUtils.lerp(n['elbow'+side].rotation.x,-.12-(thinking?1.1:Math.sin(t*.7)*.12),blend);
  n['wrist'+side].rotation.y=Math.sin(t*1.3)*.2;
  for(let f=0;f<5;f++){const curl=.18+(Math.sin(t*1.4+f*.3)+1)*.23;n['finger'+side+f].rotation.x=curl;n['tip'+side+f].rotation.x=curl*.7;}
 }
 n.jaw.rotation.x=THREE.MathUtils.lerp(n.jaw.rotation.x,speaking?.08+Math.abs(Math.sin(t*14))*(.12+level*.3):0,blend);
 n.eyeL.rotation.y=n.eyeR.rotation.y=Math.sin(t*.73)*.15;
 r.armour.forEach((m,i)=>{const k=clamp((intro-.2-i*.003)/.45,0,1);m.visible=intro>.15;m.position.copy(m.userData.rest).addScaledVector(new THREE.Vector3(Math.sin(i*7),.5,Math.cos(i*7)),(1-k)*1.5);});
 r.glow.emissiveIntensity=intro<.65?0:1.6+Math.sin(t*3)*.3+(speaking?level:0);
 r.mesh.visible=intro>.12;
 r.mesh.updateMatrixWorld(true);
}
export function animateSnake(s,t,intro=1) {
 // Procedural inverse kinematics: the independently rigged serpent follows
 // a spatial helix around the humanoid, with a travelling slither wave.
 const count=s.bones.length,up=new THREE.Vector3(0,1,0);
 const path=(i)=>{const u=i/(count-1),a=t*.55+u*Math.PI*2;
  const radius=.82+Math.sin(t*1.1-u*7)*.055;
  return new THREE.Vector3(Math.cos(a)*radius,.4+u*2.35+Math.sin(t*1.4-u*6)*.08,Math.sin(a)*radius);
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
  b.updateMatrixWorld(true);
 }
 s.head.rotation.y=Math.sin(t*1.6)*.5;s.jaw.rotation.x=.15+(Math.sin(t*2)+1)*.23;
 s.mesh.visible=intro>.72 && Math.sin(t*.12)>-.93;s.mesh.updateMatrixWorld(true);
}
export function startScene() {
 const report=(v)=>window.HologramBridge?.postMessage(JSON.stringify(v));
 let renderer;try{renderer=new THREE.WebGLRenderer({antialias:true,alpha:false,powerPreference:'low-power'});}catch(e){report({type:'error',message:'WebGL unavailable'});return;}
 document.body.appendChild(renderer.domElement);renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));renderer.setClearColor(0x01070b);
 const scene=new THREE.Scene(),camera=new THREE.PerspectiveCamera(36,1,.1,60);scene.fog=new THREE.FogExp2(0x01070b,.045);
 const ambient=new THREE.HemisphereLight(0xb8eaff,0x24404c,3.5);scene.add(ambient);
 const key=new THREE.PointLight(0x49ddff,90,12),rim=new THREE.PointLight(0x8056ff,65,12);key.position.set(2,4,3);rim.position.set(-2,3,-2);scene.add(key,rim);
 const rig=buildRig(),snake=buildSnake();scene.add(rig.mesh,snake.mesh);
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
   m.rotation.set(i*.2,i*.3,i*.4);group.add(m);
  }
 }
 let state='idle',theme='snake',introStart=performance.now(),introEnabled=true,reduced=false,paused=false,level=0,done=false,elapsed=0,last=0,fps=60,frames=0,windowStart=0;
 let yaw=0,pitch=.06,distance=7.7,drag=false,startX=0,startY=0,lastInput=0,pointers=new Map(),pinch=0;
 function applyTheme(name){theme=THEMES[name]?name:'snake';for(const [key,env] of Object.entries(environments))env.visible=key===theme;const [a,b,c]=THEMES[theme];rig.glow.color.setHex(a);rig.glow.emissive.setHex(a);key.color.setHex(a);rim.color.setHex(b);snake.material.color.setHex(b);snake.material.emissive.setHex(a);snake.material.emissiveIntensity=.2;particleMaterial.color.setHex(a);trail.material.color.setHex(a);scene.fog.color.setHex(c);renderer.setClearColor(c);}
 window.jarvisScene={update(v){if(v.state)state=v.state;if(v.theme)applyTheme(v.theme);level=clamp(Number(v.level)||0,0,1);reduced=!!v.reduceMotion;if(v.intro===false){introEnabled=false;done=true;}},skipIntro(){introEnabled=false;done=true;report({type:'introFinished'});},pause(v){paused=!!v;},snapshot(){return{engine:'Three.js r180 WebGL',state,theme,bones:rig.bones.length,snakeBones:snake.bones.length,intro:done?'done':'running',humanoidHead:rig.named.head.getWorldPosition(new THREE.Vector3()).toArray(),snakeHead:snake.head.getWorldPosition(new THREE.Vector3()).toArray(),fps,drawCalls:renderer.info.render.calls,triangles:renderer.info.render.triangles};}};
 const canvas=renderer.domElement;
 canvas.addEventListener('pointerdown',e=>{pointers.set(e.pointerId,[e.clientX,e.clientY]);if(pointers.size===1){drag=false;startX=e.clientX;startY=e.clientY;}if(pointers.size===2){const a=[...pointers.values()];pinch=Math.hypot(a[0][0]-a[1][0],a[0][1]-a[1][1]);}canvas.setPointerCapture(e.pointerId);lastInput=performance.now();});
 canvas.addEventListener('pointermove',e=>{if(!pointers.has(e.pointerId))return;const prev=pointers.get(e.pointerId);pointers.set(e.pointerId,[e.clientX,e.clientY]);if(pointers.size===2){const a=[...pointers.values()],d=Math.hypot(a[0][0]-a[1][0],a[0][1]-a[1][1]);distance=clamp(distance+(pinch-d)*.012,5,11);pinch=d;drag=true;}else{if(Math.hypot(e.clientX-startX,e.clientY-startY)>8)drag=true;if(drag){yaw+=(e.clientX-prev[0])*.006;pitch=clamp(pitch+(e.clientY-prev[1])*.004,-.25,.6);}}lastInput=performance.now();});
 canvas.addEventListener('pointerup',e=>{pointers.delete(e.pointerId);if(!drag)report({type:'tap'});lastInput=performance.now();});canvas.addEventListener('pointercancel',e=>pointers.delete(e.pointerId));
 canvas.addEventListener('wheel',e=>{e.preventDefault();distance=clamp(distance+e.deltaY*.003,5,11);lastInput=performance.now();},{passive:false});
 function resize(){const w=innerWidth,h=innerHeight;renderer.setSize(w,h);camera.aspect=w/h;camera.updateProjectionMatrix();}addEventListener('resize',resize);resize();applyTheme(theme);
 function frame(now){requestAnimationFrame(frame);if(paused||document.hidden)return;if(now-last<1000/(fps<38?30:60)-1)return;const dt=Math.min((now-last)/1000,.05);last=now;if(!reduced)elapsed+=dt;const t=elapsed;
  let intro=introEnabled&&!reduced?clamp((now-introStart)/6500,0,1):1;if(intro===1&&!done){done=true;report({type:'introFinished'});}
  animateRig(rig,t,state,level,intro,dt);animateSnake(snake,t,intro);
  if(!reduced){points.rotation.y=t*.035;ring.rotation.z=t*.1;environments[theme].children.forEach((m,i)=>{m.rotation.y=t*(theme==='inferno'?2:.2)+i*.2;m.rotation.z=Math.sin(t*.4+i)*.3;});}
  if(now-lastInput>2800&&!pointers.size){yaw*=.97;pitch+=(.06-pitch)*.03;distance+=(7.7-distance)*.03;}
  const d=distance+(1-intro)*2;camera.position.set(Math.sin(yaw)*d,2+pitch*d,Math.cos(yaw)*d);camera.lookAt(0,1.7,0);
  const p=new THREE.Vector3();snake.head.getWorldPosition(p);if(!reduced){trailPos.copyWithin(3,0,trailPos.length-3);trailPos.set([p.x,p.y,p.z],0);trailGeo.attributes.position.needsUpdate=true;trailGeo.computeBoundingSphere();}trail.visible=snake.mesh.visible;
  renderer.render(scene,camera);frames++;if(now-windowStart>2000){fps=frames*1000/(now-windowStart);frames=0;windowStart=now;if(fps<32)renderer.setPixelRatio(1);report({type:'metrics',...window.jarvisScene.snapshot()});}
 }
 requestAnimationFrame(frame);report({type:'ready'});
 addEventListener('webglcontextlost',e=>{e.preventDefault();report({type:'error',message:'WebGL context lost'});});
}
if(typeof window!=='undefined'&&!window.__HOLOGRAM_TEST__)startScene();
