const express = require('express');
const cors = require('cors');

process.env.PLAYWRIGHT_BROWSERS_PATH = '0';

const { chromium } = require('playwright');

const app = express();

app.use(cors());

const PORT = process.env.PORT || 3000;

let isScraping = false;

app.get('/', (req, res) => {
  res.json({
    status: 'ok',
    message: 'Sale Scout API Running',
  });
});

app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
  });
});

app.get('/product', async (req, res) => {
  const url = req.query.url;

  if (!url) {
    return res.status(400).json({
      error: 'Missing product URL',
    });
  }

  if (isScraping) {
    return res.status(429).json({
      error: 'Scanner busy',
    });
  }

  isScraping = true;

  let browser;

  try {
    browser = await chromium.launch({
      headless: true,
      args: [
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--no-sandbox',
      ],
    });

    const page = await browser.newPage({
      userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36',
    });

    await page.goto(url, {
      waitUntil: 'domcontentloaded',
      timeout: 90000,
    });

    await page.waitForTimeout(5000);

    const result = await page.evaluate(() => {
      const title =
        document.querySelector('h1')?.innerText ||
        document.title ||
        'Nike Product';

      return {
        title,
      };
    });

    return res.json({
      title: result.title,
      retailer: 'Nike',
      source: 'clean_reset_v2',
    });
  } catch (error) {
    console.error(error);

    return res.status(500).json({
      error: error.message,
    });
  } finally {
    isScraping = false;

    if (browser) {
      try {
        await browser.close();
      } catch (closeError) {
        console.error(closeError);
      }
    }
  }
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
