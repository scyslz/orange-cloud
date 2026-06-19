export const PRODUCT_HUNT_URL =
	"https://www.producthunt.com/products/orange-cloud?embed=true&utm_source=badge-featured&utm_medium=badge&utm_campaign=badge-orange-cloud";

/** Product Hunt 官方「Featured」徽章资源（theme=dark，宜放深色区块） */
const BADGE_SRC =
	"https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1173673&theme=dark&t=1781899090195";

/**
 * Product Hunt「Featured」徽章。图片来自 Product Hunt 官方 CDN（暗色主题）。
 * 渲染为可点击的官方 embed 链接，悬停/按下动效与 AppStoreBadge 对齐。
 */
export default function ProductHuntBadge({
	alt,
	className = "",
}: {
	alt: string;
	className?: string;
}) {
	return (
		<a
			href={PRODUCT_HUNT_URL}
			target="_blank"
			rel="noopener noreferrer"
			className={`inline-block no-underline transition-transform duration-150 ease-out hover:scale-[1.03] active:scale-[0.97] ${className}`}
		>
			{/* eslint-disable-next-line @next/next/no-img-element */}
			<img
				src={BADGE_SRC}
				alt={alt}
				width={250}
				height={54}
				style={{ height: "48px", width: "auto", display: "block" }}
			/>
		</a>
	);
}
