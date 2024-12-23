version "4.14.0"

class NMH_HitscanHandler : EventHandler
{
	override bool WorldHitscanPreFired(WorldEvent e)
	{
		if (!nmh_enabled) return false;
		
		if (e.thing && e.thing.bIsMonster && !e.thing.player && e.AttackDistance >= MISSILERANGE)
		{
			let hr = NMH_HitscanReplacer.FireReplacer(
				shooter:		e.thing,
				damage:			e.damage,
				pufftype:		e.AttackPuffType,
				damageType:		e.damageType,
				spawnheight:	e.AttackZ,
				angle:			e.AttackAngle - e.thing.angle,
				pitch:			e.AttackPitch,
				spawnofs_xy:	e.AttackOffsetSide
			);
			return hr != null;
		}
		return false;
	}
}

class NMH_HitscanReplacer : Actor
{
	//int nmh_projstyle;
	int nmh_damagefromhitscan;
	class<Actor> nmh_pufftype;
	name shooterSpecies;

	/*enum EProjStyles
	{
		PS_Tracer,
	}*/

	Default
	{
		+MISSILE
		+NOINTERACTION
		+FORCEXYBILLBOARD
		+BLOODSPLATTER
		Speed 80;
		RenderStyle 'Add';
		Height 0;
		Radius 0;
	}

	int GetProjDamage()
	{
		return ApplyDamageFactor(damageType, nmh_damagefromhitscan);
	}

	static NMH_HitscanReplacer FireReplacer(Actor shooter, int damage, class<Actor> pufftype, Name damageType, double spawnheight, double spawnofs_xy, double angle, double pitch)
	{
		if (!shooter) return null;
		if (!spawnheight) spawnheight = 32;
		let proj = NMH_HitscanReplacer(shooter.A_SpawnProjectile('NMH_HitscanReplacer',
			spawnheight: spawnheight,
			angle: angle,
			pitch: pitch,
			flags: CMF_AIMDIRECTION));
		if (proj)
		{
			proj.nmh_damagefromhitscan = damage;
			proj.nmh_pufftype = pufftype;
			proj.damageType = damageType;
		}
		return proj;
	}

	void HandleCollision()
	{
		let collision = NMH_ProjCollisionController.CheckCollision(self, self.pos, vel.Unit(), vel.Length());
		if (!collision) return;
		let hittype = collision.results.HitType;

		/*String report;
		switch (hittype)
		{
			case TRACE_HitActor:
				report = "actor";
				break;
			case TRACE_HitWall:
			case TRACE_HitFloor:
			case TRACE_HitCeiling:
				report = "geometry";
				break;
			case TRACE_HasHitSky:
				report = "sky";
				break;
			case Trace_HitNone:
				report = "nothing";
				break;
			default:
				report = "something else";
				break;
		}
		Console.Printf("Hit \cd"..report);*/

		if (hitType == TRACE_HitNone)
		{
			return;
		}

		Vector2 pAngles = (self.angle, self.pitch);
		A_Stop();
		if (hitType == TRACE_HitActor && collision.projectileVictim)
		{
			let victim = collision.projectileVictim;
			// Normally the shooter should always be there, but who knows:
			Actor source = target? target : Actor(self);

			// Get initial damage (modified by damage factor):
			int dealtDamage = GetProjDamage();
			//String dmgReportInfo = String.Format("Initial damage: \cd%d\c- (type: \cy%s\c-, dmg after factor: \cd%d\c-",nmh_damagefromhitscan, damagetype, dealtdamage);

			// Attempt to spawn the puff:
			int puffFlags = PF_HITTHING;
			if (!victim.bNOBLOOD && !victim.bDORMANT)
			{
				puffFlags |= PF_HITTHINGBLEED;
			}
			let puff = SpawnPuff(nmh_pufftype,
				pos: pos,
				hitdir: pAngles.x,
				particledir: pAngles.x + 180,
				updown: GetDefaultByType(nmh_pufftype).vel.z,
				flags: puffFlags,
				victim: victim
			);
			if (puff)
			{
				puff.A_Face(source);
				// Set puff pointers, if applicable:
				if (bHITTRACER) puff.tracer = victim;
				if (bHITMASTER) puff.master = victim;
				if (bHITTARGET) puff.target = victim;
				if (bPUFFGETSOWNER) puff.target = target;
				// Let the puff's DoSpecialDamage() modify the damage, if necessary:
				dealtDamage = puff.DoSpecialDamage(victim, dealtDamage, damagetype);
				//dmgReportInfo.AppendFormat("\c- dmg modified by puff \cd"..dealtDamage);
			}

			// Use the final damage value to deal the damage:
			dealtDamage = victim.DamageMobj(puff? puff : Actor(self), source, dealtDamage, damageType, DMG_INFLICTOR_IS_PUFF);
			//dmgReportInfo.AppendFormat("\c- final dmg dealt \cd"..dealtDamage);

			// Spawn blood decals:
			if (!victim.bNOBLOOD && !victim.bDORMANT)
			{
				victim.SpawnBlood(puff? puff.pos : pos, pAngles.x + 180, dealtDamage);
				victim.TraceBleedAngle(dealtDamage, pAngles.x, pAngles.y);
				if (puff && !puff.bPUFFONACTORS)
				{
					puff.Destroy();
				}
			}
			//Console.Printf(dmgReportInfo);
			SetStateLabel("Death");
			return;
		}

		switch (hitType)
		{
		case TRACE_HitWall:
			if (collision.results.HitLine && target)
			{
				collision.results.HitLine.RemoteActivate(target, collision.results.Side, SPAC_Impact, pos);
			}
		case TRACE_HitCeiling:
		case TRACE_HitFloor:
			name decaltype;
			let puff = SpawnPuff(nmh_pufftype,
				pos: pos,
				hitdir: pAngles.x,
				particledir: pAngles.x + 180,
				updown: GetDefaultByType(nmh_pufftype).vel.z,
				flags: 0
			);
			if (puff)
			{
				decaltype = puff.GetDecalName();
			}
			if (target && decaltype == 'none')
			{
				decaltype = target.GetDecalName();
			}
			//Console.Printf("Decal from puff: \cy%s\c-, from monster: \cy%s\c-, final: \dy%s\c-", puff.GetDecalName(), target.GetDecalName(), decaltype);
			if (decaltype != 'none')
			{
				A_SprayDecal(decaltype, collision.results.distance, direction: collision.results.hitVector);
			}
			SetStateLabel("Death");
			break;
		case TRACE_HasHitSky:
			SpawnPuff(nmh_pufftype,
				pos: pos,
				hitdir: pAngles.x,
				particledir: pAngles.x + 180,
				updown: GetDefaultByType(nmh_pufftype).vel.z,
				flags: PF_HITSKY
			);
			SetStateLabel("Null");
			break;
		}
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		alpha = nmh_alpha;
		vel = vel.Unit() * nmh_projspeed;
		A_FaceMovementDirection();
		HandleCollision();

		if (!nmh_pufftype) nmh_pufftype = 'BulletPuff';
		let puffdefs = GetDefaultByType(nmh_pufftype);
		bHITTRACER			= puffdefs.bHITTRACER;
		bHITMASTER			= puffdefs.bHITMASTER;
		bHITTARGET			= puffdefs.bHITTARGET;
		bPUFFGETSOWNER		= puffdefs.bPUFFGETSOWNER;
		bALLOWTHRUFLAGS		= puffdefs.bALLOWTHRUFLAGS;
		bTHRUSPECIES		= puffdefs.bTHRUSPECIES;
		bTHRUGHOST			= puffdefs.bTHRUGHOST;
		thruBits			= puffdefs.thruBits;
		species				= puffdefs.Species;
	}

	override void Tick()
	{
		Super.Tick();
		if (isFrozen() || !InStateSequence(curstate, spawnstate))
		{
			return;
		}

		HandleCollision();
	}

	States {
	Spawn:
		AMRK A -1 bright;
		stop;
	Death:
		TNT1 A 1;
		stop;
	}
}

class NMH_ProjCollisionController : LineTracer
{
	Actor projectileSource;
	Actor projectileVictim;

	static NMH_ProjCollisionController CheckCollision(Actor source, Vector3 start, Vector3 direction, double range)
	{
		let tracer = new('NMH_ProjCollisionController');
		tracer.projectileSource = source;
		if (tracer.Trace(start, source.cursector, direction, range,
			TRACE_HitSky,
			wallmask: Line.ML_BLOCKEVERYTHING|Line.ML_BLOCKHITSCAN,
			ignore: source) == false)
		{
			return null;
		}
		return tracer;
	}

	override ETraceStatus TraceCallback()
	{
		if (results.HitType == TRACE_HitActor && results.HitActor)
		{
			let victim = results.HitActor;
			// hit its shooter:
			if (projectileSource.target == victim)
			{
				return TRACE_Skip;
			}
			// not shotable:
			if (!victim.bSolid && !victim.bShootable)
			{
				return TRACE_Skip;
			}
			// ghost:
			if (victim.bGHOST && projectileSource.bTHRUGHOST)
			{
				return TRACE_Skip;
			}
			// +ALLOWTHRUBITS and thrubits match:
			if (projectileSource.bALLOWTHRUBITS && (projectileSource.thruBits & victim.thruBits))
			{
				return TRACE_Skip;
			}
			// +ALLOWTHRUFLAGS +THRUSPECIES and species of projectile matches species of the victim:
			if (projectileSource.bALLOWTHRUFLAGS && projectileSource.bTHRUSPECIES && projectileSource.species == victim.species)
			{
				return TRACE_Skip;
			}
			// +MTHRUSPECIES and species of the projectile's shooter match species of the victim:
			if (projectileSource.target && projectileSource.bMTHRUSPECIES && projectileSource.target.species == victim.species)
			{
				return TRACE_Skip;
			}
			projectileVictim = victim;
			return TRACE_Stop;
		}

		switch (results.HitType)
		{
			case TRACE_HitWall:
			case TRACE_HitFloor:
			case TRACE_HitCeiling:
			case TRACE_HasHitSky:
				return TRACE_Stop;
				break;
		}

		return TRACE_Skip;
	}
}