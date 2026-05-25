}
}
}

async function scrapeTarget(url) {
try {
const tcinMatch = url.match(/A-(\d+)/i);
@@ -734,22 +733,18 @@ async function scrapeTarget(url) {
`&has_financing_options=true`;

const response = await fetch(redskyUrl, {
  headers: {
    'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    Accept: '*/*',
    Referer: 'https://www.target.com/',
    Origin: 'https://www.target.com',
    'Accept-Language': 'en-US,en;q=0.9',
  },
});
      headers: {
        'User-Agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
        Accept: 'application/json',
      },
    });

if (!response.ok) {
throw new Error(`Target API failed: ${response.status}`);
}

const data = await response.json();

const product = data?.data?.product;

if (!product) {
@@ -760,61 +755,32 @@ async function scrapeTarget(url) {

const currentPrice =
parseFloat(priceData.current_retail) ||
      parseFloat(
        String(
          priceData.formatted_current_price || ''
        ).replace('$', '')
      );
      parseFloat(String(priceData.formatted_current_price || '').replace('$', ''));

const originalPrice =
parseFloat(priceData.reg_retail) ||
      parseFloat(
        String(
          priceData.formatted_comparison_price || ''
        ).replace('$', '')
      );
      parseFloat(String(priceData.formatted_comparison_price || '').replace('$', ''));

const imageUrl =
product?.item?.enrichment?.images?.primary_image_url ||
      product?.item?.enrichment?.images?.alternate_image_urls?.[0] ||
'';

    console.log(
      'TARGET IMAGE URL:',
      imageUrl
    );

return {
      title:
        product?.item?.product_description?.title ||
        'Target Product',

      title: product?.item?.product_description?.title || 'Target Product',
sku: tcin,

retailer: 'Target',

currentPrice: currentPrice || 0,

originalPrice:
        originalPrice &&
        originalPrice > currentPrice
          ? originalPrice
          : null,

      originalPriceAvailable:
        Boolean(
          originalPrice &&
          originalPrice > currentPrice
        ),

      imageUrl: imageUrl || '',

      source: 'target_redsky_api_v2',
        originalPrice && originalPrice > currentPrice ? originalPrice : null,
      originalPriceAvailable: Boolean(
        originalPrice && originalPrice > currentPrice
      ),
      imageUrl,
      source: 'target_redsky_api_v1',
};
} catch (error) {
    console.error(
      'TARGET SCRAPER ERROR:',
      error.message
    );
    console.error('TARGET SCRAPER ERROR:', error.message);

return {
title: 'Target Product',
