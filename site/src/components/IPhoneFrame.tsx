import Image from "next/image";

/**
 * Cadre d'iPhone dessiné en CSS autour d'une vraie capture de l'app.
 * L'image n'est jamais recadrée ni retouchée : l'écran prend exactement
 * les proportions de la capture (width/height), le cadre s'adapte autour.
 */
export function IPhoneFrame({
  src,
  alt,
  width,
  height,
  priority = false,
  island = true,
  className = "",
}: {
  src: string;
  alt: string;
  width: number;
  height: number;
  priority?: boolean;
  /** Pastille « Dynamic Island », posée au centre de la barre d'état (zone vide des captures). */
  island?: boolean;
  className?: string;
}) {
  return (
    <div className={`relative mx-auto w-full ${className}`} dir="ltr">
      {/* Boutons latéraux */}
      <span aria-hidden className="absolute -start-[3px] top-[16%] h-[5%] w-[3px] rounded-s-sm bg-[#2b2724]" />
      <span aria-hidden className="absolute -start-[3px] top-[24%] h-[9%] w-[3px] rounded-s-sm bg-[#2b2724]" />
      <span aria-hidden className="absolute -start-[3px] top-[35%] h-[9%] w-[3px] rounded-s-sm bg-[#2b2724]" />
      <span aria-hidden className="absolute -end-[3px] top-[27%] h-[14%] w-[3px] rounded-e-sm bg-[#2b2724]" />

      {/* Coque titane + bordure noire */}
      <div className="rounded-[3.1rem] bg-gradient-to-b from-[#4a4440] via-[#2f2a26] to-[#46403b] p-[3px] shadow-[0_50px_100px_-40px_rgba(70,45,15,.55),0_25px_60px_-30px_rgba(0,0,0,.45)]">
        <div className="rounded-[2.95rem] bg-[#0b0a09] p-[10px]">
          <div className="relative overflow-hidden rounded-[2.35rem] bg-black">
            <Image
              src={src}
              alt={alt}
              width={width}
              height={height}
              priority={priority}
              sizes="(min-width: 640px) 270px, 70vw"
              className="block h-auto w-full"
            />
            {island && (
              <span aria-hidden className="pointer-events-none absolute start-1/2 top-[1.1%] h-[3.4%] w-[30%] -translate-x-1/2 rounded-full bg-black" />
            )}
            {/* Reflet discret du verre, n'altère pas la capture */}
            <span aria-hidden className="pointer-events-none absolute inset-0 rounded-[2.35rem] ring-1 ring-inset ring-white/10" />
          </div>
        </div>
      </div>
    </div>
  );
}
