"""Controller branch tests with Odoo collaborators stubbed; no live database IO.

Run: py -3 -m unittest discover -s tool -p test_product_creation_contract.py
This does not replace Odoo/PostgreSQL integration tests.
"""
import importlib.util
from pathlib import Path
import sys
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch


def load_controller():
    odoo = ModuleType("odoo")
    odoo.http = SimpleNamespace(Controller=object, route=lambda *a, **k: lambda f: f)
    exceptions = ModuleType("odoo.exceptions")
    exceptions.AccessDenied = type("AccessDenied", (Exception,), {})
    http = ModuleType("odoo.http")
    http.request = None
    path = Path(__file__).resolve().parents[1] / "mupi_mobile_pos_api/controllers/mobile_pos_api.py"
    spec = importlib.util.spec_from_file_location("creation_controller_fixture", path)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {"odoo": odoo, "odoo.exceptions": exceptions, "odoo.http": http}):
        spec.loader.exec_module(module)
    return module


class ProductCreationContractTest(unittest.TestCase):
    def setUp(self):
        self.module = load_controller()
        self.controller = self.module.MupiMobilePosApiController()
        self.token = SimpleNamespace(scopes="product:price_update product:name_update",
                                     company_id=SimpleNamespace(id=1))
        self.controller._validate_mobile_token = MagicMock(return_value=(self.token, {}))
        self.controller._create_product_audit = MagicMock()
        self.controller._format_product = lambda p: {"id": p.id, "name": p.name}
        self.controller._product_allowed_for_token = lambda p, t: True
        self.products = MagicMock()
        empty = MagicMock()
        empty.__bool__.return_value = False
        self.products.browse.return_value = empty
        self.products.search.return_value = empty
        self.products.search_count.return_value = 0
        self.products.sudo.return_value = self.products
        self.products.with_context.return_value = self.products
        self.products.create.return_value = SimpleNamespace(id=11, name="New", lst_price=12.5, qty_available=0)
        self.taxes = MagicMock()
        self.taxes.sudo.return_value = self.taxes
        self.taxes.search.return_value = SimpleNamespace(ids=[])
        env = MagicMock()
        env.__getitem__.side_effect = {"product.product": self.products, "account.tax": self.taxes}.__getitem__
        self.module.request = SimpleNamespace(env=env)
        self.env = env

    def save(self, **kwargs):
        return self.controller.save_product(**{
            "barcode": "000123", "name": "New", "price": 12.5,
            "tax_ids": [], "create_only": True, **kwargs,
        })

    def test_create_only_never_writes_an_existing_barcode(self):
        self.products.search_count.return_value = 1
        result = self.save()
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "Barcode already exists.")
        self.products.create.assert_not_called()
        self.products.search.assert_not_called()
        self.env.cr.execute.assert_called_once_with(
            "SELECT pg_advisory_xact_lock(hashtext(%s))", ["000123"])

    def test_no_tax_explicitly_clears_odoo_defaults_on_creation(self):
        result = self.save()
        self.assertTrue(result["ok"])
        self.assertEqual(result["action"], "created")
        self.controller._validate_mobile_token.assert_called_once_with(
            required_scope="product:price_update")
        values = self.products.create.call_args.args[0]
        self.assertEqual(values["taxes_id"], [(6, 0, [])])
        self.assertEqual(values["barcode"], "000123")
        self.assertTrue(values["available_in_pos"])
        self.assertEqual(values["company_id"], 1)

    def test_invalid_or_foreign_tax_is_rejected_before_creation(self):
        for ids in (None, [True], ["1"], [-1], [999]):
            with self.subTest(ids=ids):
                self.assertFalse(self.save(tax_ids=ids)["ok"])
        self.products.create.assert_not_called()

    def test_missing_name_scope_is_rejected(self):
        self.token.scopes = "product:price_update"
        self.assertFalse(self.save()["ok"])
        self.products.create.assert_not_called()

    def test_invalid_prices_never_create_products(self):
        for price in (float("nan"), float("inf"), -1, "bad"):
            with self.subTest(price=price):
                self.assertFalse(self.save(price=price)["ok"])
        self.products.create.assert_not_called()

    def test_legacy_upsert_remains_available_without_create_only(self):
        existing = SimpleNamespace(id=7, name="Old", lst_price=2, qty_available=3, write=MagicMock())
        self.products.search.return_value = existing
        result = self.save(create_only=False)
        self.assertTrue(result["ok"])
        self.assertEqual(result["action"], "updated")
        existing.write.assert_called_once()
        self.products.create.assert_not_called()


if __name__ == "__main__":
    unittest.main()
