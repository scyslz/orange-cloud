import type { MetadataRoute } from "next";
import { routing } from "@/i18n/routing";

const SITE_URL = "https://o-c.do";

function urlFor(locale: string, path: string) {
	const prefix = locale === routing.defaultLocale ? "" : `/${locale}`;
	return `${SITE_URL}${prefix}${path}` || SITE_URL;
}

export default function sitemap(): MetadataRoute.Sitemap {
	const pages = ["", "/privacy", "/terms", "/contact"];

	return pages.map((path) => ({
		url: urlFor(routing.defaultLocale, path) || SITE_URL,
		lastModified: new Date(),
		alternates: {
			languages: Object.fromEntries(routing.locales.map((locale) => [locale, urlFor(locale, path)])),
		},
	}));
}
